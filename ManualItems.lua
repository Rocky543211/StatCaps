StatCapsManual = {};

local function T(text)
    return StatCapsLocalization.Text(text);
end

StatCapsManual.Fields = {
    { "Might", "Might" }, { "Agility", "Agility" }, { "Vitality", "Vitality" },
    { "Will", "Will" }, { "Fate", "Fate" }, { "Morale", "Max Morale" },
    { "Armour", "Armour" }, { "PhysicalMastery", "Physical Mastery" },
    { "TacticalMastery", "Tactical Mastery" }, { "CritHit", "Critical Rating" },
    { "Finesse", "Finesse" }, { "OutHeal", "Outgoing Healing" },
    { "PhysicalMitigation", "Physical Mitigation" },
    { "TacticalMitigation", "Tactical Mitigation" }, { "CritDef", "Critical Defence" },
    { "Resist", "Resistance" }, { "Block", "Block" }, { "Parry", "Parry" },
    { "Evade", "Evade" }, { "InHeal", "Incoming Healing" }, { "Hope", "Hope" },
    { "WeaponDPS", "Weapon DPS (optional)" }
};

function StatCapsManual.Parse(text)
    local values = {};
    for _, field in ipairs(StatCapsManual.Fields) do
        local input = string.match(text[field[1]] or "", "^%s*(.-)%s*$");
        local dps = field[1] == "WeaponDPS";
        if (input ~= "" and not string.match(input, "^%d+$") and
            not (dps and string.match(input, "^%d+%.%d+$"))) then
            if (dps) then return nil, "Weapon DPS: use a positive number such as 12.5, or leave blank if unknown."; end
            return nil, field[2] .. ": use whole numbers without separators (or leave blank for zero).";
        end
        values[field[1]] = input == "" and (not dps and 0 or nil) or tonumber(input);
        if (input ~= "" and (not values[field[1]] or values[field[1]] > 1000000000)) then
            return nil, field[2] .. ": number is too large.";
        end
        if (dps and values[field[1]] == 0) then return nil, "Weapon DPS must be greater than zero, or blank if unknown."; end
    end
    return values;
end

function StatCapsManual.DPSChange(old, replacement)
    if (not old and not replacement) then return nil; end
    if (not old or not replacement) then
        return "Weapon DPS: comparison unavailable. Enter DPS for both weapons (blank = unknown).";
    end
    return string.format("Weapon DPS: %.1f -> %.1f / %+.1f DPS (%+.1f%%). Separate from stat points.",
        old, replacement, replacement - old, 100 * (replacement - old) / old);
end

local derived = {
    PhysicalMastery = "PhyMas", TacticalMastery = "TacMas", CritHit = "CritHit",
    Finesse = "Finesse", OutHeal = "OutHeal", PhysicalMitigation = "PhyMit",
    TacticalMitigation = "TacMit", CritDef = "CritDef", Resist = "Resist",
    Block = "Block", Parry = "Parry", Evade = "Evade", InHeal = "InHeal", Morale = "Morale"
};

function StatCapsManual.Project(calc, className, snapshot, old, replacement)
    local projected = StatCapsComparison.Capture(snapshot.samples, snapshot.attributes, snapshot.morale, snapshot.armour);
    projected.level = snapshot.level;
    local delta = {};
    local function conversion(attribute, stat)
        return calc(className .. "CD" .. attribute .. "To" .. stat, 1);
    end
    for key, suffix in pairs(derived) do
        local value = replacement[key] - old[key];
        for _, attribute in ipairs({ "Might", "Agility", "Vitality", "Will", "Fate" }) do
            value = value + (replacement[attribute] - old[attribute]) * conversion(attribute, suffix);
        end
        if (key == "OutHeal") then
            local tactical = replacement.TacticalMastery - old.TacticalMastery;
            for _, attribute in ipairs({ "Might", "Agility", "Vitality", "Will", "Fate" }) do
                tactical = tactical + (replacement[attribute] - old[attribute]) * conversion(attribute, "TacMas");
            end
            value = value + tactical * calc(className .. "CDTacMasToOutHeal", 1);
        end
        delta[key] = value;
    end
    local armour = replacement.Armour - old.Armour;
    if (projected.armour) then projected.armour = math.max(0, projected.armour + armour); end
    delta.PhysicalMitigation = delta.PhysicalMitigation
        * calc(className .. "CDPhyMitToComPhyMit", 1)
        + armour * calc(className .. "CDArmourToComPhyMit", 1);
    delta.SpecialMitigation = (replacement.PhysicalMitigation - old.PhysicalMitigation)
        * calc(className .. "CDPhyMitToNonPhyMit", 1)
        + armour * calc(className .. "CDArmourToNonPhyMit", 1);
    -- Attribute physical-mitigation gains also apply to non-common physical damage.
    for _, attribute in ipairs({ "Might", "Agility", "Vitality", "Will", "Fate" }) do
        delta.SpecialMitigation = delta.SpecialMitigation
            + (replacement[attribute] - old[attribute]) * conversion(attribute, "PhyMit")
            * calc(className .. "CDPhyMitToNonPhyMit", 1);
    end
    delta.TacticalMitigation = delta.TacticalMitigation + armour * calc(className .. "CDArmourToTacMit", 1);
    for key, sample in pairs(projected.samples) do
        sample.rating = math.max(0, sample.rating + (delta[key] or 0));
    end
    for key, value in pairs(projected.attributes) do
        projected.attributes[key] = math.max(0, value + replacement[key] - old[key]);
    end
    if (projected.morale) then projected.morale = math.max(0, projected.morale + delta.Morale); end
    return projected;
end

function StatCapsManual.Choose(a, b)
    if (a.score ~= nil and (not b or b.score ~= nil)) then
        local best, name = a, "A";
        if (b and b.score > a.score) then best, name = b, "B"; end
        if (StatCapsScoring.ScoreState(best.score) == "DOWNGRADE") then return "Keep equipped: replacement scores lower."; end
        if (StatCapsScoring.ScoreState(best.score) == "NEUTRAL") then return "Keep equipped: no scored improvement."; end
        if (b and math.abs(a.score - b.score) <= StatCapsScoring.ScoreTolerance) then
            return "Upgrade: either slot scores equally.";
        end
        return "Prefer replacing " .. name .. ": highest build-weighted gain.";
    end
    if (a.scoreError or (b and b.scoreError)) then
        return "Cannot recommend a replacement: weighted score is incomplete.";
    end
    local function improvement(result)
        return #result.missing == 0 and #result.gains > 0 and #result.losses == 0;
    end
    if (not b) then
        return improvement(a) and "A is an improvement in measured stats."
            or "No clear upgrade over A; review the changes.";
    end
    if (improvement(a) and not improvement(b) and #b.missing == 0 and #b.gains == 0) then
        return "Prefer replacing A: useful gains without losses; B is not a clear upgrade.";
    elseif (improvement(b) and not improvement(a) and #a.missing == 0 and #a.gains == 0) then
        return "Prefer replacing B: useful gains without losses; A is not a clear upgrade.";
    end
    return "No single best replacement established. Review both results; gains in different stats are not interchangeable.";
end

function StatCapsManual.Open(getContext, getProfiles, saveCharacterItem, openLoadouts)
    local selectedProfileKey;
    local function comparisonLevel()
        if (selectedProfileKey) then
            local context = getContext(selectedProfileKey);
            return context and context.level;
        end
        local ok, level = pcall(function() return Turbine.Gameplay.LocalPlayer.GetInstance():GetLevel(); end);
        if (ok) then return level; end
        local context = getContext();
        return context and context.level;
    end
    local win = StatCapsTheme.Window();
    win:SetText(T("Stat Caps - Item comparison"));
    win:SetSize(690, 750);
    local width, height = Turbine.UI.Display.GetSize();
    win:SetPosition(math.max(0, (width - 690) / 2), math.max(0, (height - 750) / 2));
    StatCapsTheme.Panel(win, 690, 750);
    local function label(parent, text, x, y, w, h, alreadyLocalized)
        local control = Turbine.UI.Label();
        control:SetParent(parent);
        control:SetPosition(x, y);
        control:SetSize(w, h);
        control:SetFont(Turbine.UI.Lotro.Font.Verdana14);
        control:SetForeColor(Turbine.UI.Color(0.92, 0.9, 0.84));
        control:SetText(alreadyLocalized and text or T(text));
        return control;
    end
    local report = StatCapsTheme.Window();
    report:SetText(T("Stat Caps - Comparison result"));
    report:SetSize(690, 480);
    report:SetPosition(math.max(0, (width - 690) / 2), math.max(0, (height - 480) / 2));
    StatCapsTheme.Panel(report, 690, 480);
    local verdict = label(report, "", 22, 42, 646, 55);
    verdict:SetFont(Turbine.UI.Lotro.Font.Verdana18);
    local scores = label(report, "", 22, 102, 646, 70);
    scores:SetFont(Turbine.UI.Lotro.Font.Verdana16);
    local detailToggle = StatCapsTheme.Button();
    detailToggle:SetParent(report);
    detailToggle:SetPosition(22, 180);
    detailToggle:SetSize(180, 26);
    detailToggle:SetText(T("Show score details"));
    local reportList = Turbine.UI.ListBox();
    reportList:SetParent(report);
    reportList:SetPosition(22, 215);
    reportList:SetSize(626, 195);
    local reportScroll = Turbine.UI.Lotro.ScrollBar();
    reportScroll:SetParent(report);
    reportScroll:SetPosition(651, 215);
    reportScroll:SetSize(12, 195);
    reportScroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    reportList:SetVerticalScrollBar(reportScroll);
    label(report, "Stat score excludes weapon DPS, Hope, procs and set effects.\nWeapon DPS change is NOT a prediction of skill damage or total character DPS.", 22, 417, 646, 42);
    local showDetails, briefLines, detailLines = false, {}, {};
    local function RenderReport()
        detailToggle:SetText(T(showDetails and "Show short result" or "Show score details"));
        reportList:ClearItems();
        for _, paragraph in ipairs(showDetails and detailLines or briefLines) do
            paragraph = T(paragraph);
            local line = "";
            for word in string.gmatch(paragraph, "%S+") do
                if (#line + #word > 65) then
                    reportList:AddItem(label(nil, line, 0, 0, 620, 23, true));
                    line = word;
                else
                    line = line == "" and word or line .. " " .. word;
                end
            end
            reportList:AddItem(label(nil, line, 0, 0, 620, 23, true));
        end
    end
    detailToggle.Click = function()
        showDetails = not showDetails;
        RenderReport();
    end
    report:SetVisible(false);
    local picker = StatCapsTheme.Window();
    picker:SetText(T("Stat Caps - Choose item variant"));
    picker:SetSize(690, 420);
    StatCapsTheme.Panel(picker, 690, 420);
    picker:SetPosition(math.max(0, (width - 690) / 2), math.max(0, (height - 420) / 2));
    local pickerHint = label(picker, "Choose the base bonuses matching your tooltip. These are NOT verified instances.\nOnly supported records are listed. If none matches, close and enter manually.", 20, 38, 650, 45);
    local variantList = Turbine.UI.ListBox();
    variantList:SetParent(picker);
    variantList:SetPosition(20, 90);
    variantList:SetSize(630, 310);
    local variantScroll = Turbine.UI.Lotro.ScrollBar();
    variantScroll:SetParent(picker);
    variantScroll:SetPosition(654, 90);
    variantScroll:SetSize(12, 310);
    variantScroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    variantList:SetVerticalScrollBar(variantScroll);
    picker:SetVisible(false);
    local function renderCandidates(list, candidates, chooseItem, searching)
        list:ClearItems();
        for _, candidate in ipairs(candidates) do
            local summary = {};
            for _, field in ipairs(StatCapsManual.Fields) do
                local value = candidate.values[field[1]];
                if (value and value ~= 0) then summary[#summary + 1] = T(field[2]) .. " " .. value; end
            end
            local lines, line = {}, "";
            for word in string.gmatch(table.concat(summary, ", "), "%S+") do
                if (#line + #word > 70) then lines[#lines + 1], line = line, word;
                else line = line == "" and word or line .. " " .. word; end
            end
            lines[#lines + 1] = line;
            local row = Turbine.UI.Control();
            local heading = T((candidate.characterLevel and "Character level " or
                (candidate.scaling and "Calculated item level " or "Base level ")) .. candidate.level .. " / " .. (candidate.slot or "unknown slot") ..
                " / ID " .. candidate.id);
            if (searching) then heading = candidate.name .. "\n" .. heading; end
            local textHeight = (#lines + (searching and 2 or 1)) * 22;
            row:SetSize(625, textHeight + 34);
            label(row, heading .. "\n" .. table.concat(lines, "\n"), 0, 0, 620, textHeight, true);
            local choose = StatCapsTheme.Button();
            choose:SetParent(row);
            choose:SetPosition(0, textHeight + 2);
            choose:SetSize(230, 24);
            choose:SetText(T((searching and "Use item " or "Use variant ") .. candidate.id));
            choose.Click = function() chooseItem(candidate); end
            list:AddItem(row);
        end
    end
    local searchWin, searchEntry, searchLevel, searchList, searchStatus, previous, nextPage;
    local searchTarget, searchPage, searchQuery = nil, 1, "";
    local function searchItems()
        local candidates, total, err = StatCapsItemDatabase.SearchInput(searchQuery, searchPage, searchLevel:GetText(), comparisonLevel());
        if (not candidates or total == 0) then
            StatCapsManual.LastItemIssue = err or "No supported items found. Try a shorter name, or enter bonuses manually.";
        end
        searchList:ClearItems();
        previous:SetEnabled(searchPage > 1);
        nextPage:SetEnabled(candidates ~= nil and searchPage * 30 < total);
        if (not candidates) then searchStatus:SetText(T(err)); return; end
        searchStatus:SetText(T(total == 0 and "No supported items found. Try a shorter name, or enter bonuses manually." or
            total .. " matches / Page " .. searchPage .. " of " .. math.ceil(total / 30) ..
            ". Check name, level, slot and bonuses before choosing."));
        renderCandidates(searchList, candidates, function(candidate)
            searchTarget(candidate);
            searchWin:SetVisible(false);
        end, true);
    end
    local function openSearch(title, chooseItem)
        picker:SetVisible(false);
        if (not searchWin) then
            searchWin = StatCapsTheme.Window();
            searchWin:SetSize(690, 520);
            StatCapsTheme.Panel(searchWin, 690, 520);
            searchWin:SetPosition(math.max(0, (width - 690) / 2), math.max(0, (height - 520) / 2));
            label(searchWin, "Search an English name, numeric ID or pasted item link.\nItem scaling: tooltip item level. Character scaling: target level, not item level 1.", 20, 38, 650, 44);
            searchEntry = Turbine.UI.Lotro.TextBox();
            searchEntry:SetParent(searchWin);
            searchEntry:SetPosition(20, 90);
            searchEntry:SetSize(480, 26);
            searchEntry:SetMultiline(false);
            searchEntry:SetFont(Turbine.UI.Lotro.Font.Verdana14);
            searchEntry:SetBackColor(Turbine.UI.Color(0.1, 0.12, 0.16));
            searchEntry:SetForeColor(Turbine.UI.Color(1, 1, 1));
            local go = StatCapsTheme.Button();
            go:SetParent(searchWin);
            go:SetPosition(515, 90);
            go:SetSize(150, 26);
            go:SetText(T("Find items"));
            go.Click = function()
                searchQuery, searchPage = searchEntry:GetText(), 1;
                searchItems();
            end
            label(searchWin, "Item level (blank = link/base):", 20, 123, 350, 24);
            searchLevel = Turbine.UI.Lotro.TextBox();
            searchLevel:SetParent(searchWin);
            searchLevel:SetPosition(375, 123);
            searchLevel:SetSize(85, 24);
            searchLevel:SetMultiline(false);
            searchLevel:SetFont(Turbine.UI.Lotro.Font.Verdana14);
            searchStatus = label(searchWin, "", 20, 150, 650, 40);
            searchList = Turbine.UI.ListBox();
            searchList:SetParent(searchWin);
            searchList:SetPosition(20, 195);
            searchList:SetSize(630, 265);
            local searchScroll = Turbine.UI.Lotro.ScrollBar();
            searchScroll:SetParent(searchWin);
            searchScroll:SetPosition(654, 195);
            searchScroll:SetSize(12, 265);
            searchScroll:SetOrientation(Turbine.UI.Orientation.Vertical);
            searchList:SetVerticalScrollBar(searchScroll);
            previous = StatCapsTheme.Button();
            previous:SetParent(searchWin);
            previous:SetPosition(20, 477);
            previous:SetSize(150, 26);
            previous:SetText(T("Previous page"));
            previous.Click = function() searchPage = math.max(1, searchPage - 1); searchItems(); end
            nextPage = StatCapsTheme.Button();
            nextPage:SetParent(searchWin);
            nextPage:SetPosition(515, 477);
            nextPage:SetSize(150, 26);
            nextPage:SetText(T("Next page"));
            nextPage.Click = function() searchPage = searchPage + 1; searchItems(); end
            searchEntry.TextChanged = function()
                searchList:ClearItems();
                previous:SetEnabled(false);
                nextPage:SetEnabled(false);
                searchStatus:SetText(T("Click Find items to search the local database."));
            end
            searchLevel.TextChanged = searchEntry.TextChanged;
        end
        searchTarget = chooseItem;
        searchWin:SetText(T("Stat Caps - Item search / " .. title));
        searchList:ClearItems();
        previous:SetEnabled(false);
        nextPage:SetEnabled(false);
        searchStatus:SetText(T("Enter at least 2 characters, then click Find items. No item drop needed."));
        searchWin:SetVisible(true);
        searchWin:Activate();
    end
    local virtueConfirm, confirmedVirtueSignature, profilePicker;
    win.VisibleChanged = function()
        if (not win:IsVisible()) then
            report:SetVisible(false);
            picker:SetVisible(false);
            if (profilePicker) then profilePicker:SetVisible(false); end
            if (searchWin) then searchWin:SetVisible(false); end
            virtueConfirm:SetChecked(false);
            confirmedVirtueSignature = nil;
        end
    end
    local inputHint = "Type bonuses directly, or drop items to autofill. Blank = zero.\nA/B represent equipped items. Verify bonuses and matching equipment slots.";
    local hint = label(win, inputHint, 15, 35, 425, 40);
    hint:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    hint:SetForeColor(Turbine.UI.Color(0.82, 0.79, 0.71));
    local profileButton = StatCapsTheme.Button();
    profileButton:SetParent(win);
    profileButton:SetPosition(15, 78);
    profileButton:SetSize(155, 26);
    profileButton:SetText(T("Target: This character"));
    virtueConfirm = Turbine.UI.Lotro.CheckBox();
    virtueConfirm:SetParent(win);
    virtueConfirm:SetPosition(450, 41);
    virtueConfirm:SetSize(220, 30);
    virtueConfirm:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    virtueConfirm:SetText(T("I confirm saved equipped virtues"));
    virtueConfirm:SetChecked(false);
    local function virtueSignature(context)
        local parts = {};
        for index = 1, 5 do
            local choice = context.equippedVirtues[index];
            parts[#parts + 1] = choice and (choice.name .. ":" .. tostring(choice.rank)) or "-";
        end
        for _, virtue in ipairs(StatCapsVirtueData.virtues) do
            parts[#parts + 1] = virtue.name .. ":" .. tostring(context.earnedVirtueRanks[virtue.name]);
        end
        return table.concat(parts, "|");
    end
    local rowColors = {
        Turbine.UI.Color(0.07, 0.09, 0.13),
        Turbine.UI.Color(0.15, 0.19, 0.25)
    };
    local focusColor = Turbine.UI.Color(0.28, 0.22, 0.08);
    local entryFocusColor = Turbine.UI.Color(0.38, 0.29, 0.08);
    local rowBands, rowLabels, focusedEntry, focusedRow = {}, {}, nil, nil;
    for row, field in ipairs(StatCapsManual.Fields) do
        local y = 167 + (row - 1) * 18;
        local band = Turbine.UI.Control();
        band:SetParent(win);
        band:SetPosition(15, y);
        band:SetSize(645, 18);
        band:SetBackColor(rowColors[(row - 1) % 2 + 1]);
        band:SetMouseVisible(false);
        rowBands[row] = band;
        rowLabels[row] = label(win, field[2], 15, y, 160, 18);
        rowLabels[row]:SetMouseVisible(false);
    end
    local function clearFocus()
        if (focusedEntry) then
            focusedEntry:SetBackColor(rowColors[(focusedRow - 1) % 2 + 1]);
            rowBands[focusedRow]:SetBackColor(rowColors[(focusedRow - 1) % 2 + 1]);
            rowLabels[focusedRow]:SetForeColor(Turbine.UI.Color(0.9, 0.9, 0.9));
        end
        focusedEntry, focusedRow = nil, nil;
        hint:SetText(T(inputHint));
    end
    local slots = {};
    local applySavedBaseline;
    local applySavedItem;
    if (openLoadouts) then
        local loadouts = StatCapsTheme.Button();
        loadouts:SetParent(win);
        loadouts:SetPosition(15, 615);
        loadouts:SetSize(150, 26);
        loadouts:SetText(T("Compare loadouts"));
        loadouts.Click = function() openLoadouts(selectedProfileKey); end
    end
    local results = Turbine.UI.ListBox();
    results:SetParent(win);
    results:SetPosition(15, 653);
    results:SetSize(640, 62);
    local scroll = Turbine.UI.Lotro.ScrollBar();
    scroll:SetParent(win);
    scroll:SetPosition(659, 653);
    scroll:SetSize(12, 62);
    scroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    results:SetVerticalScrollBar(scroll);
    local result = {};
    function result:SetText(text)
        text = T(text or "");
        results:ClearItems();
        for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
            local line = "";
            for word in string.gmatch(paragraph, "%S+") do
                if (#line + #word > 80) then
                    results:AddItem(label(nil, line, 0, 0, 635, 20, true));
                    line = word;
                else
                    line = line == "" and word or line .. " " .. word;
                end
            end
            results:AddItem(label(nil, line, 0, 0, 635, 20, true));
        end
    end
    result:SetText("Enter bonuses for A and Replacement, then Analyze. Drops and B are optional.");
    for index, title in ipairs({ "Equipped A", "Equipped B (optional)", "Replacement" }) do
        local x = 180 + (index - 1) * 165;
        local slot = { entries = {} };
        slots[index] = slot;
        local heading = label(win, title, x, 75, 160, 20);
        heading:SetForeColor(Turbine.UI.Color(0.9, 0.8, 0.5));
        local drop = Turbine.UI.Control();
        drop:SetParent(win);
        drop:SetPosition(x, 98);
        drop:SetSize(155, 42);
        drop:SetBackColor(Turbine.UI.Color(0.18, 0.18, 0.18));
        drop:SetAllowDrop(true);
        local icon = Turbine.UI.Lotro.ItemInfoControl();
        icon:SetParent(drop);
        icon:SetSize(40, 40);
        icon:SetMouseVisible(false);
        local name = label(drop, "Optional drop", 44, 0, 110, 42);
        name:SetMouseVisible(false);
        slot.icon, slot.name = icon, name;
        local confirm = Turbine.UI.Lotro.CheckBox();
        confirm:SetParent(win);
        confirm:SetPosition(x, 142);
        confirm:SetSize(155, 20);
        confirm:SetText(T("Bonuses complete"));
        confirm:SetVisible(false);
        slot.confirm = confirm;
        local function invalidate()
            confirm:SetChecked(false);
            report:SetVisible(false);
            picker:SetVisible(false);
            if (searchWin) then searchWin:SetVisible(false); end
            result:SetText("Inputs changed. Analyze again to use the entered values.");
        end
        local function fillItem(info, data, keepOnFailure, isWorn, equipmentSlotHint, automatic, equipmentKey)
            local values, message, equipmentSlot, variants, characterLevel =
                StatCapsItemDatabase.Lookup(data, info, comparisonLevel());
            if (not values) then StatCapsManual.LastItemIssue = message; end
            if (keepOnFailure and not values and not variants) then
                if (isWorn and equipmentSlotHint) then
                    slot.info = info;
                    slot.fromWorn = true;
                    slot.equipmentKey = equipmentKey;
                    icon:SetItemInfo(info);
                    name:SetText(info:GetName());
                    slot.equipmentSlot = equipmentSlotHint;
                    slot.characterLevel = nil;
                    slot.lookup = message;
                    slot.bonusesUnknown = values == nil;
                    slot.variants = nil;
                    if (slot.worn) then slot.worn:SetText(T("Choose worn item")); end
                    invalidate();
                    result:SetText("This worn item is not in the database. Existing bonuses were kept. "
                        .. "Enter the tooltip bonuses, then Analyze.");
                    return;
                end
                result:SetText(title .. ": " .. message .. " Existing inputs are unchanged.");
                return;
            end
            slot.info = info;
            slot.fromWorn = isWorn == true;
            slot.equipmentKey = equipmentKey;
            slot.characterLevel = characterLevel;
            icon:SetItemInfo(info);
            name:SetText(info:GetName());
            for _, entry in pairs(slot.entries) do entry:SetText(""); end
            invalidate();
            slot.equipmentSlot = equipmentSlot or equipmentSlotHint;
            slot.lookup = message;
            slot.bonusesUnknown = values == nil;
            if (values) then
                for key, entry in pairs(slot.entries) do
                    entry:SetText(key == "WeaponDPS" and (values[key] and tostring(values[key]) or "") or tostring(values[key] or 0));
                end
            end
            confirm:SetChecked(false);
            result:SetText(title .. ": " .. message);
            slot.variants = variants;
            if (slot.worn) then slot.worn:SetText(T(variants and "Choose variant" or "Choose worn item")); end
            slot.chooseVariant = function(onSelected)
                if (not slot.variants) then return; end
                picker:SetText(T("Stat Caps - Choose item variant"));
                pickerHint:SetText(T("Choose the base bonuses matching your tooltip. These are NOT verified instances.\nOnly supported records are listed. If none matches, close and enter manually."));
                renderCandidates(variantList, slot.variants, function(candidate)
                    for key, entry in pairs(slot.entries) do
                        entry:SetText(key == "WeaponDPS" and (candidate.values[key] and tostring(candidate.values[key]) or "") or tostring(candidate.values[key] or 0));
                    end
                    slot.equipmentSlot = candidate.slot;
                    slot.characterLevel = candidate.characterLevel;
                    slot.bonusesUnknown, slot.variants = false, nil;
                    if (slot.worn) then slot.worn:SetText(T("Choose worn item")); end
                    slot.lookup = "User-selected base variant " .. candidate.id ..
                        ", level " .. candidate.level .. " (instance NOT verified). Check tooltip and edit if needed.";
                    invalidate();
                    result:SetText(title .. ": " .. slot.lookup);
                    if (index == 3 and applySavedBaseline) then applySavedBaseline(candidate.slot); end
                    if (onSelected) then onSelected(); end
                end, false);
                picker:SetVisible(true);
                picker:Activate();
            end
            if (variants and not automatic) then slot.chooseVariant(); end
            if (index == 3 and equipmentSlot and applySavedBaseline) then applySavedBaseline(equipmentSlot); end
        end
        slot.fillItem = fillItem;
        drop.DragDrop = function(_, args)
            local drag = args and args.DragDropInfo;
            if (drag) then drag:SetSuccessful(false); end
            local shortcut;
            local ok, info = pcall(function()
                shortcut = drag and drag:GetShortcut();
                if (not shortcut or shortcut:GetType() ~= Turbine.UI.Lotro.ShortcutType.Item) then
                    return nil;
                end
                local item = shortcut:GetItem();
                assert(item, "Cannot read the dropped item.");
                return item:GetItemInfo();
            end);
            if (ok and not info) then
                result:SetText("This drop has no readable item shortcut. Vault/storage drops may not expose one. "
                    .. "Move the item to your bag and drag again, or use Search/manual bonuses. Existing inputs are unchanged.");
                return;
            elseif (not ok) then
                result:SetText("Item drop failed: " .. tostring(info));
                return;
            end
            local readOk, data = pcall(function() return shortcut:GetData(); end);
            fillItem(info, readOk and data or nil);
        end
        for row, field in ipairs(StatCapsManual.Fields) do
            local y = 167 + (row - 1) * 18;
            local entry = Turbine.UI.Lotro.TextBox();
            entry:SetParent(win);
            entry:SetPosition(x, y);
            entry:SetSize(150, 18);
            entry:SetFont(Turbine.UI.Lotro.Font.Verdana12);
            entry:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
            entry:SetBackColor(rowColors[(row - 1) % 2 + 1]);
            entry:SetForeColor(Turbine.UI.Color(1, 1, 1));
            entry:SetMultiline(false);
            entry.FocusGained = function()
                clearFocus();
                focusedEntry, focusedRow = entry, row;
                rowBands[row]:SetBackColor(focusColor);
                rowLabels[row]:SetForeColor(Turbine.UI.Color(1, 0.88, 0.5));
                entry:SetBackColor(entryFocusColor);
                hint:SetText(T("Editing: " .. field[2] .. " - " .. title .. ". Blank = zero.\n" ..
                    "A/B represent equipped items. Verify bonuses and matching equipment slots."));
            end
            entry.FocusLost = function()
                if (focusedEntry == entry) then clearFocus(); end
            end
            entry.TextChanged = invalidate;
            slot.entries[field[1]] = entry;
        end
        local clear = StatCapsTheme.Button();
        clear:SetParent(win);
        clear:SetPosition(x, 568);
        clear:SetSize(70, 22);
        clear:SetText(T("Clear"));
        clear.Click = function()
            slot.info = nil;
            slot.lookup = nil;
            slot.equipmentSlot = nil;
            slot.equipmentKey = nil;
            slot.characterLevel = nil;
            slot.fromWorn = false;
            slot.bonusesUnknown, slot.variants = false, nil;
            if (slot.worn) then slot.worn:SetText(T("Choose worn item")); end
            icon:SetItemInfo(nil);
            name:SetText(T("Optional drop"));
            for _, entry in pairs(slot.entries) do entry:SetText(""); end
            invalidate();
        end
        slot.clear = clear.Click;
        local search = StatCapsTheme.Button();
        search:SetParent(win);
        search:SetPosition(x + 75, 568);
        search:SetSize(75, 22);
        search:SetText(T("Search"));
        search.Click = function()
            openSearch(title, function(candidate)
                slot.info = nil; -- A database choice is not a verified inventory instance.
                slot.fromWorn = false;
                slot.equipmentSlot = candidate.slot;
                slot.equipmentKey = nil;
                slot.characterLevel = candidate.characterLevel;
                slot.bonusesUnknown, slot.variants = false, nil;
                if (slot.worn) then slot.worn:SetText(T("Choose worn item")); end
                slot.lookup = (candidate.scaling and "Calculated scaling item " or "Selected database item ") .. candidate.id .. ", level " .. candidate.level ..
                    " (instance NOT verified). Check tooltip and edit if needed.";
                icon:SetItemInfo(nil);
                name:SetText(candidate.name);
                for key, entry in pairs(slot.entries) do
                    entry:SetText(key == "WeaponDPS" and (candidate.values[key] and tostring(candidate.values[key]) or "") or tostring(candidate.values[key] or 0));
                end
                invalidate();
                result:SetText(title .. ": " .. slot.lookup);
                if (index == 3 and applySavedBaseline) then
                    applySavedBaseline(candidate.slot);
                end
            end);
        end
        slot.search = search;
        if (index < 3) then
            local worn = StatCapsTheme.Button();
            worn:SetParent(win);
            worn:SetPosition(x, 590);
            worn:SetSize(150, 22);
            worn:SetText(T("Choose worn item"));
            slot.worn = worn;
            worn.Click = function()
                if (slot.variants) then slot.chooseVariant(); return; end
                if (selectedProfileKey) then
                    local context, err = getContext(selectedProfileKey);
                    if (not context) then result:SetText(err); return; end
                    local savedItems = context.savedCharacter and context.savedCharacter.items or {};
                    local choices = {};
                    for equipmentSlot, saved in pairs(savedItems) do
                        choices[#choices + 1] = { equipmentSlot = equipmentSlot, saved = saved };
                    end
                    table.sort(choices, function(a, b) return a.equipmentSlot < b.equipmentSlot; end);
                    if (#choices == 0) then
                        result:SetText("No saved equipment for this character. Load StatCaps on that character once to capture its equipment.");
                        return;
                    end
                    variantList:ClearItems();
                    picker:SetText(T("Stat Caps - Choose saved item"));
                    pickerHint:SetText(T("Saved equipment for the selected character, not the character currently logged in."));
                    for _, item in ipairs(choices) do
                        local saved, equipmentKey = item.saved, item.equipmentSlot;
                        local choice = StatCapsTheme.Button();
                        choice:SetSize(620, 30);
                        choice:SetText(T(saved.label or equipmentKey) .. ": " .. saved.name);
                        choice.Click = function()
                            applySavedItem(slot, saved, equipmentKey, context);
                            if (slot.variants) then slot.chooseVariant(); end
                        end
                        variantList:AddItem(choice);
                    end
                    picker:SetVisible(true);
                    picker:Activate();
                    return;
                end
                local items, err = StatCapsItemDatabase.Equipped(Turbine.Gameplay.LocalPlayer.GetInstance());
                if (not items) then StatCapsManual.LastItemIssue = err; end
                if (not items) then result:SetText(err); return; end
                if (#items == 0) then
                    result:SetText("No equipped items found. Use item drops or enter bonuses manually.");
                    return;
                end
                variantList:ClearItems();
                picker:SetText(T("Stat Caps - Choose worn item"));
                pickerHint:SetText(T("Choose a worn item to suggest its base bonuses.\nCheck the tooltip, item level and essences; edit the values if needed."));
                for _, item in ipairs(items) do
                    local choice = StatCapsTheme.Button();
                    choice:SetSize(620, 30);
                    choice:SetText(T(item.label) .. ": " .. item.info:GetName());
                    choice.Click = function()
                        picker:SetVisible(false);
                        fillItem(item.info, nil, true, true, item.equipmentSlot, false, item.key);
                    end
                    variantList:AddItem(choice);
                end
                picker:SetVisible(true);
                picker:Activate();
            end
            if (index == 1) then
                local saveBaseline = StatCapsTheme.Button();
                saveBaseline:SetParent(win);
                saveBaseline:SetPosition(x, 615);
                saveBaseline:SetSize(150, 22);
                saveBaseline:SetText(T("Save A as profile baseline"));
                saveBaseline.Click = function()
                    if (not selectedProfileKey and slot.fromWorn and slot.info
                        and slot.equipmentSlot) then
                        local texts, hasInput = {}, false;
                        for key, entry in pairs(slot.entries) do
                            texts[key] = entry:GetText();
                            if (texts[key]:find("%S")) then hasInput = true; end
                        end
                        if (slot.bonusesUnknown and not hasInput) then
                            result:SetText("Item bonuses are unknown. Choose the matching variant or enter the tooltip bonuses; blank values cannot confirm this item as zero.");
                            return;
                        end
                        local values, parseError = StatCapsManual.Parse(texts);
                        if (not values) then result:SetText(parseError); return; end
                        if (slot.characterLevel and slot.characterLevel ~= comparisonLevel()) then
                            result:SetText("Character level changed. Drop or search this scaling item again to update its bonuses.");
                            return;
                        end
                        if (not saveCharacterItem) then
                            result:SetText("Saving character item baselines is unavailable.");
                            return;
                        end
                        local saved, saveError = saveCharacterItem(slot.equipmentSlot,
                            slot.info:GetName(), values, slot.info:GetCategory(), slot.characterLevel, slot.equipmentKey);
                        if (not saved) then result:SetText(saveError); return; end
                        result:SetText("Saved " .. slot.info:GetName() .. " as this character's "
                            .. slot.equipmentSlot .. " baseline. Save it again after changing this item's bonuses.");
                    else
                        result:SetText("Choose a worn item for A and enter its bonuses first.");
                    end
                end
                slot.saveBaseline = saveBaseline;
            end
        end
    end
    applySavedItem = function(slot, saved, equipmentKey, context)
        slot.clear();
        if (not saved.values) then
            local info = {
                GetName = function() return saved.name; end,
                GetCategory = function() return saved.category; end
            };
            local _, _, _, variants = StatCapsItemDatabase.Lookup(nil, info, context.level);
            if (variants) then
                slot.fillItem(info, nil, false, false, saved.slot == "Shield" and "OFF_HAND" or saved.slot,
                    true, equipmentKey);
                return;
            end
        end
        slot.equipmentSlot = saved.slot == "Shield" and "OFF_HAND" or saved.slot;
        slot.equipmentKey = equipmentKey;
        slot.characterLevel = saved.characterLevel;
        slot.bonusesUnknown = saved.values == nil;
        slot.lookup = saved.confirmed ~= false and ("Saved and user-confirmed " .. saved.name .. " baseline.")
            or "Saved equipment loaded. Database bonuses are suggestions, not verified instance stats. Check or enter bonuses, then Analyze.";
        slot.name:SetText(saved.name);
        for key, entry in pairs(slot.entries) do
            entry:SetText(saved.values and (key == "WeaponDPS" and
                (saved.values[key] and tostring(saved.values[key]) or "")
                or tostring(saved.values[key] or 0)) or "");
        end
        local currentLevel = not saved.characterLevel or saved.characterLevel == context.level;
        slot.confirm:SetChecked(saved.values ~= nil and saved.confirmed ~= false and currentLevel);
        if (not currentLevel) then
            result:SetText("Character level changed. Drop or search this scaling item again to update its bonuses.");
        elseif (not saved.values) then
            result:SetText("Saved item has no supported automatic bonuses. Enter its bonuses manually; it has not been treated as zero.");
        else
            result:SetText(slot.lookup);
        end
    end
    local function askEquippedVariant()
        for index = 1, 2 do
            if (slots[index].variants) then
                slots[index].chooseVariant(askEquippedVariant);
                return;
            end
        end
    end
    applySavedBaseline = function(equipmentSlot)
        report:SetVisible(false);
        if (not selectedProfileKey) then
            local items, err = StatCapsItemDatabase.Equipped(Turbine.Gameplay.LocalPlayer.GetInstance());
            if (not items) then
                StatCapsManual.LastItemIssue = err;
                for index = 1, 2 do
                    if (slots[index].fromWorn) then slots[index].clear(); end
                end
                result:SetText(err);
                return;
            end
            local matches = {};
            for _, item in ipairs(items) do
                if (item.equipmentSlot == equipmentSlot) then
                    matches[#matches + 1] = item;
                end
            end
            for index = 1, math.min(2, #matches) do
                local item = matches[index];
                local slot = slots[index];
                local hasInput = false;
                for _, input in pairs(slot.entries) do
                    if (input:GetText():find("%S")) then hasInput = true; break; end
                end
                local sameVerified = slot.fromWorn and slot.info and hasInput
                    and slot.equipmentKey == item.key and slot.info:GetName() == item.info:GetName()
                    and slot.info:GetCategory() == item.info:GetCategory()
                    and (not slot.characterLevel or slot.characterLevel == comparisonLevel());
                if (sameVerified) then
                    slot.confirm:SetChecked(false);
                else
                    slot.clear();
                    slot.fillItem(item.info, nil, false, true, item.equipmentSlot, true, item.key);
                end
            end
            if (#matches == 1) then slots[2].clear(); end
            if (#matches == 0) then
                for index = 1, 2 do
                    if (slots[index].fromWorn) then slots[index].clear(); end
                end
                result:SetText("No matching equipped item found. Choose a worn item or enter bonuses manually.");
            else
                result:SetText("Matching equipped items loaded. Choose the exact variant for items with missing values, then Analyze.");
                askEquippedVariant();
            end
            return;
        end
        slots[1].clear();
        slots[2].clear();
        local context, err = getContext(selectedProfileKey);
        if (not context) then result:SetText(err); return; end
        local savedItems = context and context.savedCharacter and context.savedCharacter.items;
        equipmentSlot = equipmentSlot or "OFF_HAND";
        local matches = StatCapsCharacterProfiles.MatchingItems(savedItems, equipmentSlot);
        if (#matches == 0) then
            slots[1].name:SetText(T("No saved item baseline"));
            result:SetText("No saved " .. tostring(equipmentSlot)
                .. " equipment for this character. Load StatCaps on that character once to refresh its full equipment snapshot.");
            return;
        end
        for index = 1, math.min(2, #matches) do
            applySavedItem(slots[index], matches[index].item, matches[index].key, context);
        end
        askEquippedVariant();
    end
    profilePicker = StatCapsTheme.Window();
    profilePicker:SetText(T("Stat Caps - Choose comparison character"));
    profilePicker:SetSize(430, 430);
    StatCapsTheme.Panel(profilePicker, 430, 430);
    profilePicker:SetPosition(math.max(0, (width - 430) / 2), math.max(0, (height - 430) / 2));
    profilePicker:SetVisible(false);
    label(profilePicker, "Choose which character's saved stats and build to use.", 18, 38, 390, 32);
    local profileList = Turbine.UI.ListBox();
    profileList:SetParent(profilePicker);
    profileList:SetPosition(18, 78);
    profileList:SetSize(390, 320);
    local profileScroll = Turbine.UI.Lotro.ScrollBar();
    profileScroll:SetParent(profilePicker);
    profileScroll:SetPosition(412, 78);
    profileScroll:SetSize(12, 320);
    profileScroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    profileList:SetVerticalScrollBar(profileScroll);
    local function chooseProfile(key, name)
        selectedProfileKey = key;
        report:SetVisible(false);
        profileButton:SetText(T(key and ("Target: " .. name) or "Target: This character"));
        profilePicker:SetVisible(false);
        virtueConfirm:SetChecked(false);
        virtueConfirm:SetEnabled(key == nil);
        for _, slot in ipairs(slots) do
            if (slot.characterLevel) then slot.confirm:SetChecked(false); end
        end
        if (slots[1].saveBaseline) then slots[1].saveBaseline:SetEnabled(key == nil); end
        if (key) then
            local replacementSlot = slots[3].equipmentSlot or "OFF_HAND";
            applySavedBaseline(replacementSlot);
        else
            slots[1].clear();
            slots[2].clear();
            result:SetText("Comparing against this character's current stats.");
            if (slots[3].equipmentSlot) then applySavedBaseline(slots[3].equipmentSlot); end
        end
    end
    profileButton.Click = function()
        profileList:ClearItems();
        local current = StatCapsTheme.Button();
        current:SetSize(380, 34);
        current:SetText(T("This character - current live stats"));
        current.Click = function() chooseProfile(nil); end
        profileList:AddItem(current);
        for _, saved in ipairs(getProfiles and getProfiles() or {}) do
            local entry = saved;
            local choice = StatCapsTheme.Button();
            choice:SetSize(380, 38);
            choice:SetText(entry.name .. " / " .. T(entry.className) .. " / level "
                .. entry.level .. (entry.build and (" / " .. T(entry.build)) or " / no build"));
            choice.Click = function() chooseProfile(entry.key, entry.name); end
            profileList:AddItem(choice);
        end
        profilePicker:SetVisible(true);
        profilePicker:Activate();
    end
    win.OpenItemLink = function(query)
        slots[3].search.Click();
        searchLevel:SetText("");
        searchEntry:SetText(query);
        searchQuery, searchPage = query, 1;
        searchItems();
    end
    local analyze = StatCapsTheme.Button();
    analyze:SetParent(win);
    analyze:SetPosition(15, 588);
    analyze:SetSize(150, 22);
    analyze:SetText(T("Analyze"));
    analyze.Click = function()
        report:SetVisible(false);
        local context, err = getContext(selectedProfileKey);
        if (not context) then result:SetText(err); return; end
        local values = {};
        for index, slot in ipairs(slots) do
            local texts, hasInput = {}, false;
            for key, entry in pairs(slot.entries) do
                texts[key] = entry:GetText();
                if (string.find(texts[key], "%S")) then hasInput = true; end
            end
            if (index ~= 2 or slot.info or slot.equipmentKey or hasInput) then
                if (slot.characterLevel and slot.characterLevel ~= context.level) then
                    result:SetText("Character level changed. Drop or search this scaling item again to update its bonuses.");
                    return;
                end
                if (slot.bonusesUnknown and not hasInput) then
                    result:SetText("Item bonuses are unknown. Choose the matching variant or enter the tooltip bonuses; blank values cannot confirm this item as zero.");
                    return;
                end
                local parsed, parseError = StatCapsManual.Parse(texts);
                if (not parsed) then result:SetText("Slot " .. index .. ": " .. parseError); return; end
                values[index] = parsed;
            end
        end
        local comparisons, projections, adjustedVirtues = {}, {}, {};
        local canAdjustVirtues = false;
        local virtueAdjustmentError;
        if (virtueConfirm:IsChecked()) then
            local selection, selectionError = StatCapsVirtues.Validate(context.level, context.equippedVirtues);
            local ranks, ranksError = StatCapsVirtues.ValidateRanks(context.earnedVirtueRanks);
            if (not selection or not ranks) then
                virtueAdjustmentError = selectionError or ranksError;
                virtueConfirm:SetChecked(false);
                confirmedVirtueSignature = nil;
            else
                local signature = virtueSignature(context);
                if (confirmedVirtueSignature and confirmedVirtueSignature ~= signature) then
                    virtueAdjustmentError = "Saved virtues or ranks changed. Review them, then confirm again.";
                    virtueConfirm:SetChecked(false);
                    confirmedVirtueSignature = nil;
                else
                    confirmedVirtueSignature = signature;
                    canAdjustVirtues = true;
                end
            end
        else
            confirmedVirtueSignature = nil;
        end
        for index = 1, 2 do
            if (values[index]) then
                if ((slots[index].info and slots[3].info
                        and slots[index].info:GetCategory() ~= slots[3].info:GetCategory())
                    or (slots[index].equipmentSlot and slots[3].equipmentSlot
                        and slots[index].equipmentSlot ~= slots[3].equipmentSlot)) then
                    result:SetText("Item categories do not match. Compare items for the same equipment slot.");
                    return;
                end
                local projected = StatCapsManual.Project(CalcStat, context.className, context.snapshot, values[index], values[3]);
                local comparison = StatCapsComparison.Evaluate(context.profile, context.snapshot, projected);
                comparison.hopeDelta = values[3].Hope - values[index].Hope;
                comparisons[index] = comparison;
                projections[index] = projected;
                if (canAdjustVirtues) then
                    local optimized, virtueError = StatCapsVirtues.Recommend(CalcStat, context.className,
                        context.profile, projected, context.level, context.equippedVirtues, context.earnedVirtueRanks);
                    if (optimized) then
                        adjustedVirtues[index] = {
                            recommendation = optimized,
                            total = comparison.score and comparison.score + optimized.score or nil,
                            error = comparison.scoreError
                        };
                    else
                        adjustedVirtues[index] = { error = virtueError };
                    end
                elseif (virtueAdjustmentError) then
                    adjustedVirtues[index] = { error = virtueAdjustmentError };
                end
            end
        end
        report:SetText(T("Stat Caps - " .. context.profile.name .. " / " .. (context.tierName or "selected tier")));
        verdict:SetText(T(StatCapsManual.Choose(comparisons[1], comparisons[2])));
        local hasWeaponDPS = values[1].WeaponDPS or values[3].WeaponDPS or (values[2] and values[2].WeaponDPS);
        if (hasWeaponDPS) then
            verdict:SetText(T("Stats only: " .. StatCapsManual.Choose(comparisons[1], comparisons[2])));
        end
        local scoreLines = {};
        briefLines, detailLines = {}, {
            "Points are heuristic build priorities, not measured performance.",
            "Each +1% of a rating's selected-tier cap earns its weight in points. Each +1% of current max morale earns its morale weight.",
            "Only the portion below cap counts. Above-cap gains and losses staying above cap score 0.",
            "Armour and main attributes score through their derived ratings/morale only; no double counting.",
            "Weights: primary 5; tank morale 5, incoming healing/resistance 2, critical defence 1; healer morale 2; support morale 3.",
            "All builds value mitigations and class damage: tank mastery/critical 0.5; healer mastery 0.5; support mastery 1; DD mastery/critical 5.",
            ""
        };
        if (context.profile.scoring) then
            detailLines = {
                StatCapsScoring.Description(context.profile),
                "Combined weight = (class EV x 5 + role value / 5) / 6. Displayed scores are x 1,000. Armour/attributes score through derived stats only.",
                "Morale is uncapped. Weapon DPS, Hope, procs and set effects are not scored.", ""
            };
        end
        briefLines[#briefLines + 1] = StatCapsScoring.Description(context.profile) ..
            (context.profile.scoring and " Combined weight = (class EV x 5 + role value / 5) / 6." or " Legacy role weights.");
        for index = 1, 2 do
            local comparison = comparisons[index];
            if (comparison) then
                local title = index == 1 and "Replace A" or "Replace B";
                local scoreText = comparison.score and
                    (StatCapsScoring.FormatScore(comparison.score) .. " display pts (x 1,000)") or "score unavailable";
                local state = comparison.score and StatCapsScoring.ScoreState(comparison.score) or "INCOMPLETE";
                scoreLines[#scoreLines + 1] = title .. ": " .. state .. "  " .. scoreText;
                briefLines[#briefLines + 1] = title .. ": " ..
                    (slots[index].info and slots[index].info:GetName() or "manually entered bonuses");
                local dpsLine = StatCapsManual.DPSChange(values[index].WeaponDPS, values[3].WeaponDPS);
                if (dpsLine) then
                    briefLines[#briefLines + 1] = dpsLine;
                    detailLines[#detailLines + 1] = title .. " / " .. dpsLine;
                end
                local adjusted = adjustedVirtues[index];
                if (adjusted) then
                    if (adjusted.total) then
                        local verdict = StatCapsScoring.ScoreState(adjusted.total);
                        local line = string.format("Item + best legal virtue set: %s %s combined display points (x 1,000; item-only %s; virtue adjustment %s).",
                            verdict, StatCapsScoring.FormatScore(adjusted.total),
                            StatCapsScoring.FormatScore(comparison.score),
                            StatCapsScoring.FormatScore(adjusted.recommendation.score));
                        briefLines[#briefLines + 1] = line;
                        detailLines[#detailLines + 1] = line;
                        local function setNames(choices)
                            local names = {};
                            for _, choice in pairs(choices) do
                                names[#names + 1] = choice.name .. " rank " .. choice.rank;
                            end
                            table.sort(names);
                            return #names > 0 and table.concat(names, ", ") or "None";
                        end
                        local change = "Virtues: " .. setNames(adjusted.recommendation.selection) ..
                            " -> " .. setNames(adjusted.recommendation.choices);
                        briefLines[#briefLines + 1] = change;
                        detailLines[#detailLines + 1] = change;
                    else
                        local line = "Virtue-adjusted comparison unavailable: " .. adjusted.error;
                        briefLines[#briefLines + 1] = line;
                        detailLines[#detailLines + 1] = line;
                    end
                end
                if (comparison.hopeDelta ~= 0) then
                    local hopeWarning = "Hope " .. string.format("%+d", comparison.hopeDelta) ..
                        " (" .. values[index].Hope .. " -> " .. values[3].Hope ..
                        " item bonus). NOT scored: check Dread and other Hope sources.";
                    briefLines[#briefLines + 1] = hopeWarning;
                    detailLines[#detailLines + 1] = hopeWarning;
                    scoreLines[#scoreLines] = scoreLines[#scoreLines] ..
                        " / Hope " .. string.format("%+d", comparison.hopeDelta) .. " unscored";
                end
                if (not slots[index].info or not slots[3].info) then
                    detailLines[#detailLines + 1] = "Manual comparison: equipment-slot compatibility is not verified.";
                end
                detailLines[#detailLines + 1] = title .. " / " .. scoreText;
                if (comparison.scoreError) then
                    briefLines[#briefLines + 1] = comparison.scoreError;
                    detailLines[#detailLines + 1] = comparison.scoreError;
                end
                for rank, item in ipairs(comparison.scoreDetails) do
                    local line = item.label .. ": " .. string.format("%+.1f", item.delta) ..
                        " (" .. StatCapsScoring.FormatScore(item.points) .. " display pts)";
                    if (rank <= 3) then briefLines[#briefLines + 1] = line; end
                    detailLines[#detailLines + 1] = line .. " / useful " ..
                        string.format("%+.1f", item.useful) .. " / weight " .. item.weight ..
                        (item.classWeight and item.roleWeight and
                            (" ((" .. item.classWeight .. " x 5 + " .. item.roleWeight .. "/5) / 6)") or "") ..
                        " / reference " .. string.format("%.1f", item.reference);
                end
                local projected = projections[index];
                if (context.snapshot.armour and projected.armour) then
                    local armourLine = "Armour: " .. string.format("%.0f -> %.0f", context.snapshot.armour, projected.armour);
                    briefLines[#briefLines + 1] = armourLine .. " (valued through mitigations)";
                    detailLines[#detailLines + 1] = armourLine ..
                        "; points included in mitigation changes above.";
                end
                if (context.snapshot.morale and projected.morale) then
                    briefLines[#briefLines + 1] = "Max Morale: " ..
                        string.format("%.0f -> %.0f", context.snapshot.morale, projected.morale);
                end
                local scored = {};
                for _, item in ipairs(comparison.scoreDetails) do scored[item.label] = true; end
                for _, item in ipairs(comparison.other) do
                    if (not scored[item.label]) then
                        detailLines[#detailLines + 1] = item.label .. ": " ..
                            string.format("%+.1f", item.delta) .. " / no separate points for this build.";
                    end
                end
                for _, item in ipairs(comparison.attributes) do
                    detailLines[#detailLines + 1] = item.label .. ": " ..
                        string.format("%+.1f", item.delta) .. " / points included in derived bonuses.";
                end
                if (slots[index].lookup) then detailLines[#detailLines + 1] = slots[index].lookup; end
                detailLines[#detailLines + 1] = "";
            end
        end
        if (comparisons[1] and comparisons[2]
            and comparisons[1].score ~= nil and comparisons[2].score ~= nil) then
            local scoreGap = comparisons[1].score - comparisons[2].score;
            local lead = math.abs(scoreGap) <= StatCapsScoring.ScoreTolerance and "tied"
                or (scoreGap > 0 and "A ahead" or "B ahead");
            scoreLines[#scoreLines + 1] = "A vs B: " .. StatCapsScoring.FormatScore(scoreGap) ..
                " display pts (" .. lead .. ")";
        end
        if (slots[3].lookup) then
            detailLines[#detailLines + 1] = "Replacement source: " .. slots[3].lookup;
        end
        scores:SetText(T(table.concat(scoreLines, "\n")));
        briefLines[#briefLines + 1] = "Above-cap gains earn 0 points. Use score details for the full breakdown.";
        showDetails = false;
        RenderReport();
        report:SetVisible(true);
        report:Activate();
        result:SetText("Analysis ready in the Comparison result window.");
    end
    win:SetVisible(true);
    win:Activate();
    return win;
end
