StatCapsItemDatabase = {};
local loaded = false;
local uniqueNames = {};
local variantsByName = {};
local searchIndex = {};
local recordIDs = {};
local integerStats = {
    Might = true, Agility = true, Vitality = true, Will = true, Fate = true, Armour = true
};
StatCapsItemDatabase.ArmourTypes = { "All armour", "Light", "Medium", "Heavy", "Shield", "Heavy shield", "Warden shield" };
StatCapsItemDatabase.Qualities = { "All qualities", "Common", "Uncommon", "Rare", "Incomparable", "Legendary" };

local function matchesFilters(record, filters, level)
    if (not filters) then return true; end
    local restrictions = record[8] or {};
    if (filters.className and restrictions.className and restrictions.className ~= filters.className) then return false; end
    if (filters.atLevel and restrictions.minimum and restrictions.minimum > level) then return false; end
    -- Field 10 packs quality and armour type into one small numeric value.
    local metadata = record[10] or 0;
    return (not filters.armour or metadata % 8 == filters.armour)
        and (not filters.quality or math.floor(metadata / 8) == filters.quality);
end

function StatCapsItemDatabase.Equipped(player)
    local ok, items = pcall(function()
        local equipment = player:GetEquipment();
        local result = {};
        local seen = {};
        for _, slot in ipairs({
            { "Head", "Head", "HEAD" }, { "Shoulder", "Shoulders", "SHOULDER" },
            { "Back", "Back", "BACK" }, { "Chest", "Chest", "CHEST" },
            { "Gloves", "Hands", "HAND" }, { "Legs", "Legs", "LEGS" },
            { "Boots", "Feet", "FEET" }, { "Necklace", "Necklace", "NECK" },
            { "Earring1", "Earring 1", "EAR" }, { "Earring2", "Earring 2", "EAR" },
            { "Bracelet1", "Bracelet 1", "WRIST" }, { "Bracelet2", "Bracelet 2", "WRIST" },
            { "Ring1", "Ring 1", "FINGER" }, { "Ring2", "Ring 2", "FINGER" },
            { "Pocket", "Pocket", "POCKET" },
            { "PrimaryWeapon", "Main hand", "MAIN_HAND" },
            { "SecondaryWeapon", "Off hand", "OFF_HAND" },
            { "Shield", "Shield", "OFF_HAND" },
            { "RangedWeapon", "Ranged weapon", "RANGED_ITEM" }, { "Class", "Class item", "CLASS" }
        }) do
            local id = Turbine.Gameplay.Equipment[slot[1]];
            local item = id ~= nil and equipment:GetItem(id);
            if (item and not seen[id]) then
                seen[id] = true;
                result[#result + 1] = {
                    key = slot[1], label = slot[2], info = item:GetItemInfo(), equipmentSlot = slot[3]
                };
            end
        end
        return result;
    end);
    if (not ok) then
        return nil, "Cannot read equipped items. Use item drops or enter bonuses manually: " .. tostring(items);
    end
    return items;
end

local function load()
    if (not loaded) then
        local ok, err = pcall(import, "StatCaps.ItemRecords");
        if (not ok or type(StatCapsItemRecords) ~= "table") then
            return nil, "Database load failed: " .. tostring(err) .. ". Enter bonuses manually.";
        end
        local scalingOk, scalingError = pcall(import, "StatCaps.ItemScaling");
        if (not scalingOk or type(StatCapsItemCurves) ~= "table") then
            return nil, "Database load failed: " .. tostring(scalingError) .. ". Enter bonuses manually.";
        end
        for id, record in pairs(StatCapsItemRecords) do
          -- Legendary placeholders share one record across their source IDs; index it once.
          if (not recordIDs[record]) then
            recordIDs[record] = id;
            -- Uniqueness covers all source equipment, including excluded variants.
            if (record[5]) then uniqueNames[record[1]] = record; end
            variantsByName[record[1]] = variantsByName[record[1]] or {};
            table.insert(variantsByName[record[1]], { id = id, record = record });
            searchIndex[#searchIndex + 1] = { id = id, record = record, name = string.lower(record[1]) };
          end
        end
        table.sort(searchIndex, function(a, b)
            if (a.name ~= b.name) then return a.name < b.name; end
            if (a.record[2] ~= b.record[2]) then return a.record[2] < b.record[2]; end
            return a.id < b.id;
        end);
        loaded = true;
    end
    return true;
end

function StatCapsItemDatabase.ProgressionValue(curve, level)
    if (not curve) then return nil; end
    if (curve[1] == "A") then
        local index = level - curve[2] + 3;
        if (index < 3 or index > #curve) then return nil; end
        return curve[index];
    end
    for i = 2, #curve - 2, 2 do
        local x1, y1, x2, y2 = curve[i], curve[i + 1], curve[i + 2], curve[i + 3];
        if (level >= x1 and level <= x2) then
            return y1 + (y2 - y1) * (level - x1) / (x2 - x1);
        end
    end
end

function StatCapsItemDatabase.Identity(id)
    local ok, err = load();
    if (not ok) then return nil, err; end
    local record = StatCapsItemRecords[id];
    if (record) then return { name = record[1], category = record[3], slot = record[6] }; end
end

function StatCapsItemDatabase.Values(record, itemLevel, characterLevel)
    if (not record[7]) then
        local values = {};
        for key, value in pairs(record[4]) do values[key] = value; end
        return values, record[2];
    end
    local spec = record[7];
    local character = spec[4] == "character";
    local level = character and characterLevel or (not character and (itemLevel or record[2]));
    if (character and (type(level) ~= "number" or level % 1 ~= 0 or level < 1 or level > 160)) then
        return nil, "A character level from 1 to 160 is required for this item.";
    end
    if (type(level) ~= "number" or level % 1 ~= 0 or level < spec[1] or level > spec[2]) then
        return nil, character and ("Character level is outside this item's supported scaling range: "
            .. spec[1] .. "-" .. spec[2] .. ".")
            or "Item level is outside this item's supported scaling range.";
    end
    local values = {};
    for _, stat in ipairs(spec[3]) do
        local value, banded;
        if (type(stat[2]) == "table") then
            banded = true;
            for _, band in ipairs(stat[2]) do
                if (level >= band[1] and level <= band[2]) then
                    value = StatCapsItemDatabase.ProgressionValue(StatCapsItemCurves[band[3]], level);
                    banded = false;
                    break;
                end
            end
        elseif (type(stat[2]) == "number") then
            value = stat[2];
        else
            value = StatCapsItemDatabase.ProgressionValue(StatCapsItemCurves[stat[2]], level);
        end
        if (not banded) then
            if (not value or value ~= value or value < 0 or value == math.huge) then
                return nil, "No supported progression value at this item level. Enter bonuses manually.";
            end
            local displayed = stat[1] == "WeaponDPS" and math.floor(value * 10 + 0.5) / 10
                or math.floor(value + (integerStats[stat[1]] and 0 or 0.5));
            values[stat[1]] = (values[stat[1]] or 0) + displayed;
        end
    end
    return values, level;
end

local function copyCandidate(id, record, itemLevel, characterLevel)
    local values, level = StatCapsItemDatabase.Values(record, itemLevel, characterLevel);
    if (not values) then return nil, level; end
    return { id = id, name = record[1], level = level, category = record[3],
        values = values, slot = record[6], scaling = record[7] ~= nil, legendary = record[9] == true,
        itemLevel = record[7] and record[7][4] == "character" and record[2] or level,
        restrictions = record[8],
        characterLevel = record[7] and record[7][4] == "character" and level or nil };
end

function StatCapsItemDatabase.Search(query, page, itemLevel, characterLevel, slot, filters)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or "";
    if (#query < 2) then return nil, 0, "Enter at least 2 characters of an item name, or its numeric ID."; end
    if (itemLevel ~= nil and (type(itemLevel) ~= "number" or itemLevel % 1 ~= 0 or itemLevel < 1 or itemLevel > 999)) then
        return nil, 0, "Enter a whole item level from 1 to 999, or leave it blank.";
    end
    page = tonumber(page) or 1;
    if (page < 1 or page % 1 ~= 0) then return nil, 0, "Invalid search page."; end
    if (filters ~= nil and (type(filters) ~= "table"
        or (filters.atLevel and (type(characterLevel) ~= "number" or characterLevel % 1 ~= 0 or characterLevel < 1))
        or (filters.className ~= nil and type(filters.className) ~= "string")
        or (filters.armour ~= nil and (type(filters.armour) ~= "number" or filters.armour % 1 ~= 0 or filters.armour < 1 or filters.armour > 6))
        or (filters.quality ~= nil and (type(filters.quality) ~= "number" or filters.quality % 1 ~= 0 or filters.quality < 1 or filters.quality > 5)))) then
        return nil, 0, "Invalid item filters or target character level.";
    end
    local ok, err = load();
    if (not ok) then return nil, 0, err; end
    query = string.lower(query);
    local results, total = {}, 0;
    local first, last = (page - 1) * 30 + 1, page * 30;
    local index = searchIndex;
    local exact = query:match("^%d+$") and tonumber(query);
    if (exact and StatCapsItemRecords[exact]) then
        -- Exact IDs include aliases that share another ID's search row.
        local record = StatCapsItemRecords[exact];
        index = { { id = exact, record = record, name = string.lower(record[1]) } };
    end
    for _, candidate in ipairs(index) do
        local spec = candidate.record[7];
        if ((candidate.name:find(query, 1, true) or tostring(candidate.id) == query)
            and (not slot or StatCapsLoadouts.SlotFits(slot, candidate.record[6]))
            and matchesFilters(candidate.record, filters, characterLevel)
            -- An entered item level hides item-level records that cannot exist at that level.
            and not (itemLevel and spec and spec[4] ~= "character" and (itemLevel < spec[1] or itemLevel > spec[2]))) then
            total = total + 1;
            if (total >= first and total <= last) then
                local result, valueError = copyCandidate(candidate.id, candidate.record, itemLevel, characterLevel);
                if (not result) then return nil, 0, valueError; end
                results[#results + 1] = result;
            end
        end
    end
    return results, total;
end

-- Recalculates an item-level scaling record for the tooltip item level; nil for any other record.
function StatCapsItemDatabase.Rescale(id, itemLevel)
    local ok, err = load();
    if (not ok) then return nil, err; end
    local record = id and StatCapsItemRecords[id];
    if (not record or not record[7] or record[7][4] == "character") then return nil; end
    return StatCapsItemDatabase.Values(record, itemLevel);
end

function StatCapsItemDatabase.SearchInput(query, page, levelText, characterLevel, slot, filters)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or "";
    levelText = type(levelText) == "string" and levelText:match("^%s*(.-)%s*$") or "";
    local level = levelText ~= "" and tonumber(levelText) or nil;
    if (levelText ~= "" and not level) then
        return nil, 0, "Enter a whole item level from 1 to 999, or leave it blank.";
    end
    if (query:sub(1, 1) == "<") then
        local link, err = StatCapsItemLinks.Parse(query);
        if (not link) then return nil, 0, err; end
        if (link.level and level and link.level ~= level) then
            return nil, 0, "Entered item level differs from the link. Clear the item-level field to use the link.";
        end
        query, level = tostring(link.id), link.level or level;
    end
    return StatCapsItemDatabase.Search(query, page, level, characterLevel, slot, filters);
end

function StatCapsItemDatabase.Lookup(data, info, characterLevel)
    -- Never interpret opaque instance identifiers as static item IDs.
    local idHex = type(data) == "string" and string.match(data, "^0[xX]0,0[xX](%x+)$");
    local ok, err = load();
    if (not ok) then return nil, err; end
    local record = idHex and StatCapsItemRecords[tonumber(idHex, 16)];
    local suggested = not idHex;
    if (suggested) then record = uniqueNames[info:GetName()]; end
    if (not record) then
        if (suggested) then
            local variants = {};
            for _, candidate in ipairs(variantsByName[info:GetName()] or {}) do
                local base = candidate.record;
                if (base[3] == info:GetCategory()) then
                    local choice, err = copyCandidate(candidate.id, base, nil, characterLevel);
                    if (not choice) then return nil, err; end
                    variants[#variants + 1] = choice;
                end
            end
            table.sort(variants, function(a, b) return a.id < b.id; end);
            if (#variants > 0) then
                return nil, "Ambiguous name: choose a base variant; none is verified. Enter manually if none matches.",
                    nil, variants;
            end
        end
        return nil, "No unique supported base record (unknown item or variants). Enter bonuses manually.";
    end
    if (record[1] ~= info:GetName() or record[3] ~= info:GetCategory()) then
        return nil, "Database identity differs (language/update/variant). Enter bonuses manually.";
    end
    local values, valueError = StatCapsItemDatabase.Values(record, nil, characterLevel);
    if (not values) then return nil, valueError; end
    return values, (suggested and "Suggested base by unique name/category (instance NOT verified). "
        or "Static ID matched. ") .. (record[7] and record[7][4] == "character"
            and ("Character level " .. valueError .. " (item level " .. record[2] .. "). ")
            or ("Base item level " .. record[2] .. ". ")) ..
        "Check tooltip/essences and confirm.", record[6], nil,
        record[7] and record[7][4] == "character" and valueError or nil,
        recordIDs[record], record[2], record[8];
end
