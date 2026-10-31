StatCapsSetDatabase = {};
local loaded = false;
local names = {};

local function load()
    if (loaded) then return true; end
    local ok, err = pcall(import, "StatCaps.SetRecords");
    if (not ok or type(StatCapsSetRecords) ~= "table" or type(StatCapsSetItems) ~= "table"
        or type(StatCapsSetCurves) ~= "table") then
        return nil, "Set database load failed: " .. tostring(err);
    end
    for id, item in pairs(StatCapsSetItems) do
        if (item.unique) then names[item.name] = id; end
    end
    loaded = true;
    return true;
end

function StatCapsSetDatabase.Resolve(item)
    local ok, err = load();
    if (not ok) then return nil, err; end
    if (item.noSet) then return {}, true; end
    if (item.setId) then
        if (not StatCapsSetRecords[item.setId]) then return nil, "Unknown equipment set ID."; end
        return { item.setId }, true, item.id or item.name;
    end
    local id = item.id or names[item.name];
    local record = id and StatCapsSetItems[id];
    local matched;
    if (record) then
        matched, err = StatCapsCompanion.MatchesName(id, record.name, item.name);
        if (matched == nil) then return nil, err; end
    end
    if (record and matched
        and (not item.category or record.category == item.category)) then
        return record.sets, true, id;
    end
    if (record) then return nil, "Set item identity differs. Check its ID, name and category: " .. item.name; end
    if (item.id) then
        local identity;
        identity, err = StatCapsItemDatabase.Identity(item.id);
        if (err) then return nil, err; end
        if (identity) then
            matched, err = StatCapsCompanion.MatchesName(item.id, identity.name, item.name);
            if (matched == nil) then return nil, err; end
            if (not matched or (item.category and identity.category ~= item.category)) then
                return nil, "Set item identity differs. Check its ID, name and category: " .. item.name;
            end
            return {}, true;
        end
    end
    return {}, false;
end

function StatCapsSetDatabase.Search(query, pieces, slot)
    local ok, err = load();
    if (not ok) then return nil, err; end
    query = type(query) == "string" and query:match("^%s*(.-)%s*$"):lower() or "";
    if (#query < 2) then return nil, "Enter at least 2 characters of a name, or a numeric ID."; end
    local results = {};
    local translations;
    if (pieces) then
        translations, err = StatCapsCompanion.Names();
        if (not translations) then return nil, err; end
    end
    query = StatCapsCompanion.Normalize(query);
    for id, record in pairs(pieces and StatCapsSetItems or StatCapsSetRecords) do
        local translated = translations and translations[id];
        if ((tostring(id) == query or StatCapsCompanion.Normalize(record.name):find(query, 1, true)
                or (translated and StatCapsCompanion.Normalize(translated):find(query, 1, true)))
            and (not pieces or not slot or StatCapsLoadouts.SlotFits(slot, record.slot))) then
            results[#results + 1] = {
                id = id, name = record.name, displayName = translated or record.name, slot = record.slot, category = record.category,
                itemLevel = record.itemLevel, sets = record.sets
            };
        end
    end
    table.sort(results, function(a, b)
        if (a.name ~= b.name) then return a.name < b.name; end
        return a.id < b.id;
    end);
    return results;
end

function StatCapsSetDatabase.Calculate(equipment, level, manualSets)
    if (type(level) ~= "number" or level % 1 ~= 0 or level < 1 or level > 160) then
        return nil, "Set calculation requires a character level from 1 to 160.";
    end
    local ok, err = load();
    if (not ok) then return nil, err; end
    local groups, unknown = {}, {};
    for slot, item in pairs(equipment) do
        local sets, known, identity = StatCapsSetDatabase.Resolve(item);
        if (not sets) then return nil, known; end
        if (not known) then unknown[#unknown + 1] = item.name; end
        for _, id in ipairs(sets) do
            groups[id] = groups[id] or { distinct = {}, items = {} };
            groups[id].distinct[identity or item.id or item.name or slot] = true;
            groups[id].items[#groups[id].items + 1] = item;
        end
    end
    local total, rows, warnings = {}, {}, {};
    for id, group in pairs(groups) do
        local set = StatCapsSetRecords[id];
        local count = 0;
        for _ in pairs(group.distinct) do count = count + 1; end
        local eligible = level >= set.minimum and (not set.maximum or level <= set.maximum);
        local statLevel = set.level;
        local needsAverage = false;
        for _, bonus in ipairs(set.bonuses) do
            if (eligible and count >= bonus.count and set.average and not (manualSets and manualSets[id])) then
                for _, spec in ipairs(bonus.specs) do
                    if (type(spec[2]) == "string") then needsAverage = true; end
                end
            end
        end
        if (needsAverage) then
            local sum = 0;
            for _, item in ipairs(group.items) do
                if (type(item.itemLevel) ~= "number" or item.itemLevel % 1 ~= 0
                    or item.itemLevel < 1 or item.itemLevel > 999) then
                    return nil, "Set bonus needs verified item levels for: " .. set.name;
                end
                sum = sum + item.itemLevel;
            end
            statLevel = math.floor(sum / #group.items);
        end
        for _, bonus in ipairs(set.bonuses) do
            local row = { id = id, name = set.name, count = count, threshold = bonus.count,
                active = eligible and count >= bonus.count, values = {}, warnings = {} };
            if (row.active) then
                if (manualSets and manualSets[id]) then
                    row.manual = true;
                    row.warnings[#row.warnings + 1] = "Automatic totals disabled; enter this set in manual set bonuses.";
                else
                    for _, spec in ipairs(bonus.specs) do
                        local value = type(spec[2]) == "number" and spec[2]
                            or StatCapsItemDatabase.ProgressionValue(StatCapsSetCurves[spec[2]], statLevel);
                        if (type(value) ~= "number" or value ~= value or value < 0 or value == math.huge) then
                            return nil, "Set progression unavailable. Check item levels or use manual set bonuses for: " .. set.name;
                        end
                        value = math.floor(value + ((spec[1] == "Might" or spec[1] == "Agility"
                            or spec[1] == "Vitality" or spec[1] == "Will" or spec[1] == "Fate"
                            or spec[1] == "Armour") and 0 or 0.5));
                        row.values[spec[1]] = (row.values[spec[1]] or 0) + value;
                        total[spec[1]] = (total[spec[1]] or 0) + value;
                    end
                end
                for _, warning in ipairs(bonus.warnings) do row.warnings[#row.warnings + 1] = warning; end
                for _, warning in ipairs(row.warnings) do
                    warnings[#warnings + 1] = set.name .. " / " .. bonus.count .. ": " .. warning;
                end
            end
            rows[#rows + 1] = row;
        end
    end
    table.sort(rows, function(a, b)
        if (a.name ~= b.name) then return a.name < b.name; end
        return a.threshold < b.threshold;
    end);
    table.sort(unknown);
    return { values = total, rows = rows, warnings = warnings, unknown = unknown };
end
