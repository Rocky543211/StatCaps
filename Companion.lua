StatCapsCompanion = {};
local dictionaries = {};
local englishNames = {};
local casePairs = {
    ["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü", ["É"] = "é", ["È"] = "è",
    ["Ê"] = "ê", ["Ë"] = "ë", ["À"] = "à", ["Â"] = "â", ["Î"] = "î",
    ["Ï"] = "ï", ["Ô"] = "ô", ["Ù"] = "ù", ["Û"] = "û", ["Ç"] = "ç", ["Œ"] = "œ"
};
local function T(text) return StatCapsLocalization.Text(text); end

function StatCapsCompanion.Names(language)
    language = language or StatCapsLocalization.Locale();
    if (language ~= "de" and language ~= "fr") then return englishNames; end
    if (not dictionaries[language]) then
        local suffix = language:upper();
        local ok, err = pcall(import, "StatCaps.ItemNames" .. suffix);
        local names;
        if (language == "de") then names = StatCapsItemNamesDE; else names = StatCapsItemNamesFR; end
        if (not ok or type(names) ~= "table") then return nil, "Translated item names could not be loaded: " .. tostring(err); end
        dictionaries[language] = names;
    end
    return dictionaries[language];
end

function StatCapsCompanion.Name(id, fallback)
    local names, err = StatCapsCompanion.Names();
    if (not names) then return nil, err; end
    return names[id] or fallback;
end

function StatCapsCompanion.MatchesName(id, english, name)
    if (name == english) then return true; end
    local translated, err = StatCapsCompanion.Name(id, english);
    if (not translated) then return nil, err; end
    return translated == name;
end

function StatCapsCompanion.Normalize(text)
    return (text:gsub("[\194-\244][\128-\191]+", function(letter) return casePairs[letter] or letter; end)):lower();
end

function StatCapsCompanion.Sources(id)
    if (type(id) ~= "number" or id % 1 ~= 0) then return nil, "Choose an exact database item before viewing sources."; end
    if (type(StatCapsItemSources) ~= "table" or type(StatCapsSourceDescriptions) ~= "table") then
        local ok, err = pcall(import, "StatCaps.ItemSources");
        if (not ok or type(StatCapsItemSources) ~= "table" or type(StatCapsSourceDescriptions) ~= "table") then
            return nil, "Item sources could not be loaded: " .. tostring(err);
        end
    end
    return StatCapsItemSources[id] or {};
end

local function label(parent, text, x, y, width, height)
    local widget = Turbine.UI.Label();
    widget:SetParent(parent); widget:SetPosition(x, y); widget:SetSize(width, height);
    widget:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    widget:SetForeColor(Turbine.UI.Color(0.92, 0.9, 0.84)); widget:SetText(text);
    return widget;
end
local function textHeight(text, minimum)
    local height = 0;
    for line in (text .. "\n"):gmatch("(.-)\n") do height = height + math.max(1, math.ceil(#line / 70)) * 20; end
    return math.max(minimum or 24, height + 8);
end
local function window(title, height)
    height = height or 520;
    local win = StatCapsTheme.Window();
    win:SetText(T(title)); win:SetSize(690, height); StatCapsTheme.Panel(win, 690, height);
    local displayWidth, displayHeight = Turbine.UI.Display.GetSize();
    win:SetPosition(math.max(0, (displayWidth - 690) / 2), math.max(0, (displayHeight - height) / 2));
    return win;
end
local function list(parent)
    local items = Turbine.UI.ListBox();
    items:SetParent(parent); items:SetPosition(22, 150); items:SetSize(620, 310);
    local scroll = Turbine.UI.Lotro.ScrollBar();
    scroll:SetParent(parent); scroll:SetPosition(648, 150); scroll:SetSize(12, 310);
    scroll:SetOrientation(Turbine.UI.Orientation.Vertical); items:SetVerticalScrollBar(scroll);
    return items, scroll;
end

function StatCapsCompanion.OpenSources(id, name)
    local win = window("Stat Caps - Item sources");
    local rows = list(win);
    label(win, name .. " / ID " .. tostring(id), 22, 43, 633, 40);
    label(win, T("Known Companion sources, not a complete list. Availability, costs and loot conditions can change."),
        22, 85, 633, 60);
    local sources, err = StatCapsCompanion.Sources(id);
    if (not sources) then
        rows:AddItem(label(nil, T(err), 0, 0, 610, 90));
    elseif (#sources == 0) then
        rows:AddItem(label(nil, T("No acquisition source is recorded for this item. This does not mean it is unavailable."), 0, 0, 610, 90));
    else
        for _, group in ipairs(sources) do
            rows:AddItem(label(nil, T(group[1]) .. ": " .. group[2] .. T(" known sources"), 0, 0, 610, 28));
            for _, index in ipairs(group[3]) do
                local text = StatCapsSourceDescriptions[index][2];
                rows:AddItem(label(nil, text, 0, 0, 610, textHeight(text, 45)));
            end
            if (group[2] > #group[3]) then
                rows:AddItem(label(nil, T("Showing examples only; further sources are recorded."), 0, 0, 610, 30));
            end
        end
    end
    win:SetVisible(true); win:Activate();
    return win;
end

local function loadBonuses()
    if (type(StatCapsBonusRecords) ~= "table" or type(StatCapsBonusCurves) ~= "table"
        or type(StatCapsBonusWarnings) ~= "table" or type(StatCapsBonusKinds) ~= "table"
        or type(StatCapsBonusRestrictions) ~= "table") then
        local ok, err = pcall(import, "StatCaps.BonusRecords");
        if (not ok or type(StatCapsBonusRecords) ~= "table" or type(StatCapsBonusCurves) ~= "table"
            or type(StatCapsBonusWarnings) ~= "table" or type(StatCapsBonusKinds) ~= "table"
            or type(StatCapsBonusRestrictions) ~= "table") then
            return nil, "Essence and consumable data could not be loaded: " .. tostring(err);
        end
    end
    return true;
end

function StatCapsCompanion.SearchBonuses(kind, query, level, itemLevel, page)
    if (kind ~= "essence" and kind ~= "consumable") then return nil, 0, "Invalid bonus category."; end
    if (type(level) ~= "number" or level % 1 ~= 0 or level < 1 or level > 160) then return nil, 0, "Choose a supported character level first."; end
    if (itemLevel ~= nil and (type(itemLevel) ~= "number" or itemLevel % 1 ~= 0 or itemLevel < 1 or itemLevel > 999)) then
        return nil, 0, "Enter a whole item level from 1 to 999, or leave it blank.";
    end
    page = page or 1;
    if (type(page) ~= "number" or page % 1 ~= 0 or page < 1) then return nil, 0, "Invalid search page."; end
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or "";
    if (#query < 2) then return nil, 0, "Enter at least 2 characters of an item name, or its numeric ID."; end
    local ok, err = loadBonuses();
    if (not ok) then return nil, 0, err; end
    local names;
    names, err = StatCapsCompanion.Names();
    if (not names) then return nil, 0, err; end
    query = StatCapsCompanion.Normalize(query);
    local matches = {};
    for id, record in pairs(StatCapsBonusRecords) do
        if (StatCapsBonusKinds[id] == kind and (tostring(id) == query
            or StatCapsCompanion.Normalize(record[1]):find(query, 1, true)
            or (names[id] and StatCapsCompanion.Normalize(names[id]):find(query, 1, true)))) then
            matches[#matches + 1] = { id = id, name = record[1], displayName = names[id] or record[1], record = record };
        end
    end
    table.sort(matches, function(a, b)
        if (a.displayName ~= b.displayName) then return a.displayName < b.displayName; end
        return a.id < b.id;
    end);
    local results = {};
    for index = (page - 1) * 20 + 1, math.min(page * 20, #matches) do
        local candidate = matches[index];
        candidate.values, candidate.level = StatCapsItemDatabase.Values(candidate.record, itemLevel, level, StatCapsBonusCurves);
        candidate.warnings = StatCapsBonusWarnings[candidate.id];
        local rule = StatCapsBonusRestrictions[candidate.id] or {};
        candidate.usable = (not rule.minLevel or level >= rule.minLevel) and (not rule.maxLevel or level <= rule.maxLevel);
        results[#results + 1] = candidate;
    end
    return results, #matches;
end

function StatCapsCompanion.AddBonuses(values, bonus, count)
    if (type(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > 10) then return nil, "Enter a quantity from 1 to 10."; end
    if (type(bonus) ~= "table" or next(bonus) == nil) then return nil, "No supported flat bonuses are available."; end
    local keys = {};
    for _, field in ipairs(StatCapsManual.Fields) do if (field[1] ~= "WeaponDPS") then keys[field[1]] = true; end end
    local sum = {};
    for key, value in pairs(values) do sum[key] = value; end
    for key, value in pairs(bonus) do
        if (not keys[key] or type(value) ~= "number" or value ~= value or value < 0
            or value == math.huge or value % 1 ~= 0) then
            return nil, "Invalid essence or consumable bonuses.";
        end
        sum[key] = (sum[key] or 0) + value * count;
    end
    return sum;
end

function StatCapsCompanion.OpenBonuses(kind, level, onAdd)
    local win = window(kind == "essence" and "Stat Caps - Choose essence" or "Stat Caps - Plan consumables", 590);
    local rows, scroll = list(win);
    rows:SetPosition(22, 208); scroll:SetPosition(648, 208);
    local query = Turbine.UI.Lotro.TextBox();
    query:SetParent(win); query:SetPosition(22, 43); query:SetSize(460, 26); query:SetMultiline(false);
    query:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    local status = label(win, T("Search by name or ID. Check the tooltip before adding bonuses."), 22, 163, 633, 40);
    local confirmed = Turbine.UI.Lotro.CheckBox();
    confirmed:SetParent(win); confirmed:SetPosition(22, 78); confirmed:SetSize(633, 28);
    confirmed:SetText(T(kind == "essence" and "I checked the essence type, socket count and omitted effects."
        or "I verified current/planned totals and buff compatibility."));
    label(win, T(kind == "essence" and "Adds flat essence bonuses to the editor, not your character. Do not include the same essences in item bonuses and extras."
        or "Current contains only consumables already in the snapshot. Planned replaces those bonuses. Unchanged buffs go on both sides or neither."), 22, 109, 633, 50);
    local itemLevel, quantity;
    if (kind == "essence") then
        itemLevel = Turbine.UI.Lotro.TextBox();
        itemLevel:SetParent(win); itemLevel:SetPosition(330, 550); itemLevel:SetSize(70, 26); itemLevel:SetMultiline(false);
        label(win, T("Essence level:"), 225, 551, 102, 24);
        quantity = Turbine.UI.Lotro.TextBox();
        quantity:SetParent(win); quantity:SetPosition(482, 550); quantity:SetSize(40, 26);
        quantity:SetMultiline(false); quantity:SetText("1");
        label(win, T("Count:"), 418, 551, 64, 24);
    end
    local page, nextPage, previous, sourcesWindow = 1;
    local function search()
        rows:ClearItems();
        local raw = itemLevel and itemLevel:GetText():match("^%s*(.-)%s*$") or "";
        if (raw ~= "" and not tonumber(raw)) then status:SetText(T("Enter a whole item level from 1 to 999, or leave it blank.")); return; end
        local results, total, err = StatCapsCompanion.SearchBonuses(kind, query:GetText(), level, raw ~= "" and tonumber(raw) or nil, page);
        previous:SetEnabled(page > 1); nextPage:SetEnabled(results ~= nil and page * 20 < total);
        if (not results) then status:SetText(T(err)); return; end
        status:SetText(T("Results: ") .. total .. " / " .. T("Page ") .. page);
        for _, candidate in ipairs(results) do
            local row = Turbine.UI.Control();
            local description = candidate.displayName .. " / ID " .. candidate.id;
            if (candidate.values) then
                local fields = {};
                for _, field in ipairs(StatCapsManual.Fields) do
                    if (candidate.values[field[1]]) then fields[#fields + 1] = T(field[2]) .. ": " .. candidate.values[field[1]]; end
                end
                description = description .. "\n" .. T(kind == "consumable" and "Character level: " or "Essence item level: ")
                    .. tostring(kind == "consumable" and level or candidate.level) .. "\n" .. table.concat(fields, ", ");
            else description = description .. "\n" .. T(candidate.level); end
            if (not candidate.usable) then description = description .. "\n" .. T("Outside this consumable or essence's character-level requirements."); end
            if (#candidate.warnings > 0) then description = description .. "\n" .. T("Not compared: ") .. table.concat(candidate.warnings, ", "); end
            local height = textHeight(description, 100);
            row:SetSize(610, height + 38);
            label(row, description, 0, 0, 610, height);
            local add = StatCapsTheme.Button(); add:SetParent(row); add:SetPosition(0, height + 2); add:SetSize(190, 26);
            add:SetText(T("Add flat bonuses"));
            add:SetEnabled(candidate.usable and candidate.values ~= nil and next(candidate.values) ~= nil);
            add.Click = function()
                if (not confirmed:IsChecked()) then status:SetText(T("Confirm the tooltip and double-counting check first.")); return; end
                local count = quantity and tonumber(quantity:GetText()) or 1;
                if (not count or count % 1 ~= 0 or count < 1 or count > 10) then status:SetText(T("Enter a quantity from 1 to 10.")); return; end
                local ok, err = onAdd(candidate.values, count, candidate);
                if (not ok) then status:SetText(T(err)); return; end
                win:SetVisible(false);
            end
            local source = StatCapsTheme.Button(); source:SetParent(row); source:SetPosition(210, height + 2); source:SetSize(190, 26);
            source:SetText(T("Item sources")); source.Click = function()
                if (sourcesWindow) then sourcesWindow:SetVisible(false); end
                sourcesWindow = StatCapsCompanion.OpenSources(candidate.id, candidate.displayName);
            end
            rows:AddItem(row);
        end
    end
    local go = StatCapsTheme.Button(); go:SetParent(win); go:SetPosition(502, 43); go:SetSize(155, 26);
    go:SetText(T("Find")); go.Click = function() page = 1; search(); end
    previous = StatCapsTheme.Button(); previous:SetParent(win); previous:SetPosition(22, 550); previous:SetSize(170, 26);
    previous:SetText(T("Previous page")); previous.Click = function() page = math.max(1, page - 1); search(); end
    nextPage = StatCapsTheme.Button(); nextPage:SetParent(win); nextPage:SetPosition(535, 550); nextPage:SetSize(122, 26);
    nextPage:SetText(T("Next page")); nextPage.Click = function() page = page + 1; search(); end
    local function invalidate()
        rows:ClearItems(); previous:SetEnabled(false); nextPage:SetEnabled(false); confirmed:SetChecked(false);
        status:SetText(T("Search by name or ID. Check the tooltip before adding bonuses."));
    end
    query.TextChanged = invalidate;
    if (itemLevel) then itemLevel.TextChanged = invalidate; end
    win.VisibleChanged = function() if (not win:IsVisible() and sourcesWindow) then sourcesWindow:SetVisible(false); end end
    previous:SetEnabled(false); nextPage:SetEnabled(false);
    win:SetVisible(true); win:Activate();
    return win;
end
