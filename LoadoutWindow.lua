StatCapsLoadoutWindow = {};

local function T(text)
    return StatCapsLocalization.Text(text);
end

local function window(title, width, height)
    local win = StatCapsTheme.Window();
    win:SetText(T(title));
    win:SetSize(width, height);
    StatCapsTheme.Panel(win, width, height);
    local screenWidth, screenHeight = Turbine.UI.Display.GetSize();
    win:SetPosition(math.max(0, (screenWidth - width) / 2), math.max(0, (screenHeight - height) / 2));
    return win;
end

local function label(parent, text, x, y, width, height, literal)
    local value = Turbine.UI.Label();
    value:SetParent(parent);
    value:SetPosition(x, y);
    value:SetSize(width, height);
    value:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    value:SetForeColor(Turbine.UI.Color(0.92, 0.9, 0.84));
    value:SetText(literal and text or T(text));
    return value;
end

local function button(parent, text, x, y, width, handler, literal)
    local value = StatCapsTheme.Button();
    value:SetParent(parent);
    value:SetPosition(x, y);
    value:SetSize(width, 28);
    value:SetText(literal and text or T(text));
    value.Click = handler;
    return value;
end

local function entry(parent, x, y, width)
    local value = Turbine.UI.Lotro.TextBox();
    value:SetParent(parent);
    value:SetPosition(x, y);
    value:SetSize(width, 24);
    value:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    value:SetMultiline(false);
    value:SetBackColor(Turbine.UI.Color(0.1, 0.12, 0.16));
    value:SetForeColor(Turbine.UI.Color(1, 1, 1));
    return value;
end

local function list(parent, x, y, width, height)
    local value = Turbine.UI.ListBox();
    value:SetParent(parent);
    value:SetPosition(x, y);
    value:SetSize(width - 16, height);
    local scroll = Turbine.UI.Lotro.ScrollBar();
    scroll:SetParent(parent);
    scroll:SetPosition(x + width - 13, y);
    scroll:SetSize(12, height);
    scroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    value:SetVerticalScrollBar(scroll);
    return value;
end

local function addText(target, text, width, literal)
    local line = "";
    for word in (literal and text or T(text)):gmatch("%S+") do
        if (#line + #word > (width > 680 and 88 or 75)) then
            target:AddItem(label(nil, line, 0, 0, width, 22, true));
            line = word;
        else
            line = line == "" and word or line .. " " .. word;
        end
    end
    target:AddItem(label(nil, line, 0, 0, width, 22, true));
end

local function valuesText(values)
    local parts = {};
    for _, field in ipairs(StatCapsManual.Fields) do
        local value = values[field[1]];
        if (value and value ~= 0) then parts[#parts + 1] = T(field[2]) .. " " .. value; end
    end
    return #parts > 0 and table.concat(parts, ", ") or T("No flat stat bonus");
end

local function sameEquipment(left, right)
    for _, slot in ipairs(StatCapsLoadouts.Slots) do
        local old, new = left[slot[1]], right[slot[1]];
        if ((old == nil) ~= (new == nil)) then return false; end
        if (old and new) then
            for _, key in ipairs({ "name", "id", "category", "characterLevel", "itemLevel" }) do
                if (old[key] ~= new[key]) then return false; end
            end
            for _, field in ipairs(StatCapsManual.Fields) do
                if ((old.values and old.values[field[1]]) ~= (new.values and new.values[field[1]])) then
                    return false;
                end
            end
        end
    end
    return true;
end

function StatCapsLoadoutWindow.Open(getContext, getProfiles, getPlan, savePlan, initialTarget)
    local win = window("Stat Caps - Full loadout planner", 760, 730);
    local report = window("Stat Caps - Loadout result", 760, 650);
    local editor = window("Stat Caps - Loadout item", 690, 640);
    local search = window("Stat Caps - Loadout search", 690, 480);
    local setsWindow = window("Stat Caps - Loadout set bonuses", 690, 560);
    local setPrompt = window("Stat Caps - Set/Essence bonuses before comparison", 650, 340);
    local targets = window("Stat Caps - Choose comparison character", 430, 430);
    for _, child in ipairs({ report, editor, search, setsWindow, setPrompt, targets }) do child:SetVisible(false); end
    local context, state, selectedTarget, selectedSlot;
    local plans, activePlans = {}, {};
    selectedTarget, selectedSlot = initialTarget, StatCapsLoadouts.Slots[1];
    local status = label(win, "", 22, 665, 716, 55);
    local targetButton;
    local gearPanel = Turbine.UI.Control();
    gearPanel:SetParent(win);
    gearPanel:SetPosition(22, 154);
    gearPanel:SetSize(716, 378);
    win.gearSlots = {};
    label(win, "Drop replacements into Planned. An empty planned slot keeps your current item.\nClick an item to edit its values or choose its exact variant.", 22, 79, 716, 32);
    local missingLabel = label(win, "", 22, 112, 716, 24);
    for _, heading in ipairs({
        { "Current jewellery", 22 }, { "Planned jewellery", 194 },
        { "Current armour", 392 }, { "Planned armour", 564 }
    }) do
        label(win, heading[1], heading[2], 136, 172, 18):SetFont(Turbine.UI.Lotro.Font.Verdana12);
    end
    local selectedLabel = label(win, "", 22, 534, 716, 16);
    local setsChecked = Turbine.UI.Lotro.CheckBox();
    setsChecked:SetParent(win);
    setsChecked:SetPosition(218, 608);
    setsChecked:SetSize(270, 18);
    setsChecked:SetText(T("Set bonuses checked"));
    local renderGear, openEditor, openSearch, renderSets, calculate, applyEditor, openSetPrompt;
    local resumeCalculation = false;
    local resumeSetReview = false;
    local confirmedVirtueSignature;
    local virtueConfirm = Turbine.UI.Lotro.CheckBox();
    virtueConfirm:SetParent(win);
    virtueConfirm:SetPosition(22, 614);
    virtueConfirm:SetSize(716, 16);
    virtueConfirm:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    virtueConfirm:SetText(T("Include virtue swaps (I confirm saved equipped virtues and ranks)"));
    local function virtueSignature(value)
        local parts = { tostring(selectedTarget), tostring(value.level) };
        for index = 1, 5 do
            local choice = value.equippedVirtues and value.equippedVirtues[index];
            parts[#parts + 1] = choice and (tostring(choice.name) .. ":" .. tostring(choice.rank)) or "-";
        end
        for _, virtue in ipairs(StatCapsVirtueData.virtues) do
            parts[#parts + 1] = virtue.name .. ":" .. tostring(value.earnedVirtueRanks and value.earnedVirtueRanks[virtue.name]);
        end
        return table.concat(parts, "|");
    end
    virtueConfirm.CheckedChanged = function()
        confirmedVirtueSignature = virtueConfirm:IsChecked() and context and virtueSignature(context) or nil;
        report:SetVisible(false);
        win.lastResult = nil;
    end
    local draft, editingSide, editingSlot, loadingEditor, searchMode, searchPage, searchVariants;
    local itemName = entry(editor, 22, 70, 455);
    local nameLabel = label(editor, "Item name", 22, 43, 455, 22);
    local levelLabel = label(editor, "Item level", 500, 43, 155, 22);
    local extrasHelp = label(editor, "", 22, 43, 633, 85);
    extrasHelp:SetVisible(false);
    local itemLevel = entry(editor, 500, 70, 155);
    local identity = label(editor, "", 22, 105, 633, 24);
    local editorStatus = label(editor, "", 22, 585, 633, 38);
    local editorConfirmed = Turbine.UI.Lotro.CheckBox();
    editorConfirmed:SetParent(editor);
    editorConfirmed:SetPosition(22, 510);
    editorConfirmed:SetSize(400, 28);
    editorConfirmed:SetText(T("Bonuses complete"));
    editorConfirmed:SetVisible(false);
    local editorEntries = {};
    for index, field in ipairs(StatCapsManual.Fields) do
        local column, row = math.floor((index - 1) / 11), (index - 1) % 11;
        local x, y = 22 + column * 323, 184 + row * 24;
        label(editor, field[2], x, y + 2, 187, 22):SetFont(Turbine.UI.Lotro.Font.Verdana12);
        local input = entry(editor, x + 190, y, 113);
        input:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleRight);
        editorEntries[field[1]] = input;
        input.TextChanged = function()
            if (not loadingEditor) then editorConfirmed:SetChecked(false); end
        end
    end
    local editorHelp = label(editor, "Enter full item bonuses, including essences, not character totals.\nManual set additions must contain only bonuses not already counted automatically. Percentages and procs are not flat ratings.", 22, 459, 633, 46);
    local searchItem, searchPiece, setAssignment, setOnly;
    local bonusWindow, sourcesWindow, consumableButton, bestGearWindow;
    local persistPlan;

    local function changed()
        report:SetVisible(false);
        win.lastResult = nil;
        state.setsConfirmed = false;
        setsChecked:SetChecked(state.setsConfirmed);
        status:SetText(T("Plan updated. Compare when ready."));
        if (persistPlan) then return persistPlan(); end
    end

    local function targetKey()
        return selectedTarget or (context and context.characterName);
    end
    win.GetCurrentPlan = function(key)
        if (state and key == targetKey()) then return StatCapsLoadouts.Serialize(state); end
        local cached = activePlans[key];
        if (cached and cached.state) then return StatCapsLoadouts.Serialize(cached.state); end
        return plans[key];
    end
    persistPlan = function()
        local key = targetKey();
        if (not state or not key) then return; end
        local data = StatCapsLoadouts.Serialize(state);
        plans[key] = data;
        if (savePlan) then
            local ok, err = savePlan(key, data);
            if (not ok) then
                status:SetText(T("Plan kept in this window, but saving failed: ") .. T(tostring(err)));
                return nil;
            end
        end
        return true;
    end

    local function editorValues()
        local text = {};
        for key, input in pairs(editorEntries) do text[key] = input:GetText(); end
        return StatCapsManual.Parse(text);
    end

    local function fillEditor()
        loadingEditor = true;
        itemName:SetText(draft.name);
        itemLevel:SetText(draft.itemLevel and tostring(draft.itemLevel) or "");
        identity:SetText(T("Source item ID: ") .. tostring(draft.id or "-"));
        local assigned = draft.noSet and T("No equipment set")
            or (draft.setId and StatCapsSetRecords and StatCapsSetRecords[draft.setId]
                and StatCapsSetRecords[draft.setId].name or T("Automatic set membership"));
        setAssignment:SetText(T("Set: ") .. assigned);
        for key, input in pairs(editorEntries) do
            local value = draft.values and draft.values[key];
            input:SetText(value ~= nil and tostring(value) or "");
        end
        editorConfirmed:SetChecked(draft.confirmed);
        loadingEditor = false;
    end

    itemName.TextChanged = function()
        if (not loadingEditor and draft and itemName:GetText() ~= draft.name) then
            draft.name, draft.id, draft.restrictions = itemName:GetText(), nil, nil;
            draft.setId, draft.noSet = nil, false;
            identity:SetText(T("Source item ID: ") .. "-");
            setAssignment:SetText(T("Set: ") .. T("Automatic set membership"));
            editorConfirmed:SetChecked(false);
        end
    end
    itemLevel.TextChanged = function()
        if (not loadingEditor) then
            editorConfirmed:SetChecked(false);
            local level = tonumber(itemLevel:GetText():match("^%s*(%d+)%s*$") or "");
            local values, err;
            if (draft and draft.id and level) then values, err = StatCapsItemDatabase.Rescale(draft.id, level); end
            if (values) then
                draft.values, draft.itemLevel = values, level;
                fillEditor();
                editorStatus:SetText(T("Bonuses recalculated for item level ") .. level .. T(". Check the tooltip, then Apply."));
            elseif (err) then
                editorStatus:SetText(T(err));
            else
                editorStatus:SetText(T("Changing item level does not recalculate these fields. Search again or enter the tooltip bonuses."));
            end
        end
    end
    local function useCandidate(candidate)
        if (not StatCapsLoadouts.SlotFits(editingSlot[3], candidate.slot)) then
            editorStatus:SetText(T("Item does not fit the selected equipment slot: ") .. T(editingSlot[2]));
            return;
        end
        local original = state.original[editingSlot[1]];
        local matched, matchError = true;
        if (original) then matched, matchError = StatCapsCompanion.MatchesName(candidate.id, candidate.name, original.name); end
        if (matched == nil) then editorStatus:SetText(T(matchError)); return; end
        if (editingSide == "original" and original and
            (not matched
                or (original.category and candidate.category ~= original.category))) then
            editorStatus:SetText(T("Keep the equipped item's identity. Search its correct variant or enter its bonuses manually."));
            return;
        end
        draft = StatCapsLoadouts.CopyItem({
            name = editingSide == "original" and original and original.name or candidate.name, slot = editingSlot[3], category = candidate.category, values = candidate.values,
            id = candidate.id, itemLevel = candidate.itemLevel or candidate.level,
            characterLevel = candidate.characterLevel, restrictions = candidate.restrictions,
            icon = candidate.icon or (original and matched and original.icon or nil),
            iconLayers = candidate.iconLayers or (original and matched and original.iconLayers or nil)
        });
        fillEditor();
        search:SetVisible(false);
        editorStatus:SetText(T(candidate.legendary and "Legendary placeholder: its stats are not compared."
            or candidate.scaling and not candidate.characterLevel
                and "Bonuses use the item level shown. If the tooltip differs, type its item level."
            or candidate.values and "Database bonuses loaded. Edit if needed, then Apply."
            or "Set piece identified, but its bonuses are unsupported. Enter all bonuses manually."));
        if (searchMode == "variants" and candidate.values) then
            editorConfirmed:SetChecked(true);
            applyEditor();
        end
    end

    local query = entry(search, 22, 45, 470);
    local searchStatus = label(search, "", 22, 115, 633, 42);
    local searchList = list(search, 22, 163, 633, 241);
    local previous, nextPage;
    local targetFilter, armourFilter, qualityFilter;
    local variantLevel = entry(search, 350, 82, 70);
    local variantLevelLabel = label(search, "Tooltip item level (not character level):", 22, 82, 320, 26);
    variantLevelLabel:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    variantLevel:SetVisible(false); variantLevelLabel:SetVisible(false);
    local function searchItems()
        searchList:ClearItems();
        local results, total, err;
        if (searchMode == "items") then
            results, total, err = StatCapsItemDatabase.SearchInput(query:GetText(), searchPage, itemLevel:GetText(),
                context.level, editingSlot[3], {
                    className = targetFilter:IsChecked() and context.className or nil,
                    atLevel = targetFilter:IsChecked(),
                    armour = armourFilter.choice > 1 and armourFilter.choice - 1 or nil,
                    quality = qualityFilter.choice > 1 and qualityFilter.choice - 1 or nil
                });
        elseif (searchMode == "variants") then
            local candidates;
            candidates, err = StatCapsItemDatabase.RelevelCandidates(searchVariants, variantLevel:GetText(), context.level);
            if (candidates) then
                results, total = {}, #candidates;
                for index = (searchPage - 1) * 30 + 1, math.min(searchPage * 30, total) do
                    results[#results + 1] = candidates[index];
                end
            end
        else
            local all;
            all, err = StatCapsSetDatabase.Search(query:GetText(), searchMode == "pieces", editingSlot[3]);
            if (all) then
                results, total = {}, #all;
                for index = (searchPage - 1) * 30 + 1, math.min(searchPage * 30, total) do
                    results[#results + 1] = all[index];
                end
            end
        end
        previous:SetEnabled(searchPage > 1);
        nextPage:SetEnabled(results ~= nil and searchPage * 30 < (total or 0));
        if (not results) then searchStatus:SetText(T(err)); return; end
        searchStatus:SetText(T("Results: ") .. total .. " / " .. T("Page ") .. searchPage
            .. ((searchMode == "items" or searchMode == "pieces") and (" / " .. T(editingSlot[2])) or ""));
        for _, candidate in ipairs(results) do
            local row = Turbine.UI.Control();
            row:SetSize(612, 122);
            label(row, candidate.displayName or candidate.name, 0, 0, 455, 40, true);
            label(row, tostring(candidate.id) .. (candidate.itemLevel and
                (" / " .. T("Item level") .. " " .. candidate.itemLevel) or ""), 0, 43, 455, 22, true);
            if (candidate.legendary) then
                label(row, T("Legendary placeholder: its stats are not compared."), 0, 68, 455, 50, true);
            elseif (candidate.values) then label(row, valuesText(candidate.values), 0, 68, 455, 50, true); end
            button(row, "Select", 466, 23, 137, function()
                if (searchMode == "sets") then
                    draft.setId, draft.noSet = candidate.id, false;
                    setAssignment:SetText(T("Set: ") .. candidate.name);
                    editorConfirmed:SetChecked(false);
                    search:SetVisible(false);
                elseif (searchMode == "pieces") then
                    local found, _, valueError = StatCapsItemDatabase.Search(tostring(candidate.id), 1,
                        tonumber(itemLevel:GetText()), context.level, editingSlot[3]);
                    if (not found) then searchStatus:SetText(T(valueError)); return; end
                    useCandidate(found[1] or candidate);
                else
                    useCandidate(candidate);
                end
            end);
            if (searchMode ~= "sets") then
                button(row, "Item sources", 466, 60, 137, function()
                    if (sourcesWindow) then sourcesWindow:SetVisible(false); end
                    sourcesWindow = StatCapsCompanion.OpenSources(candidate.id, candidate.displayName or candidate.name);
                end);
            end
            searchList:AddItem(row);
        end
    end
    button(search, "Find", 510, 45, 145, function() searchPage = 1; searchItems(); end);
    previous = button(search, "Previous page", 22, 421, 150, function()
        searchPage = math.max(1, searchPage - 1); searchItems();
    end);
    nextPage = button(search, "Next page", 505, 421, 150, function()
        searchPage = searchPage + 1; searchItems();
    end);
    query.TextChanged = function()
        searchList:ClearItems();
        previous:SetEnabled(false);
        nextPage:SetEnabled(false);
        searchStatus:SetText(T("Enter a name, numeric ID or item link, then click Find."));
    end
    variantLevel.TextChanged = function()
        searchList:ClearItems(); previous:SetEnabled(false); nextPage:SetEnabled(false);
        searchStatus:SetText(T("Item level changed. Click Find to recalculate variants before choosing."));
    end
    targetFilter = Turbine.UI.Lotro.CheckBox();
    targetFilter:SetParent(search);
    targetFilter:SetPosition(22, 82);
    targetFilter:SetSize(225, 26);
    targetFilter:SetText(T("Target class + level"));
    targetFilter:SetChecked(false);
    targetFilter.CheckedChanged = query.TextChanged;
    armourFilter = StatCapsTheme.ChoiceButton(search, "Armour", StatCapsItemDatabase.ArmourTypes,
        249, 82, 190, query.TextChanged);
    qualityFilter = StatCapsTheme.ChoiceButton(search, "Quality", StatCapsItemDatabase.Qualities,
        447, 82, 208, query.TextChanged);
    openSearch = function(mode, variants)
        if (bonusWindow) then bonusWindow:SetVisible(false); end
        searchMode, searchPage = mode, 1;
        searchVariants = variants;
        query:SetEnabled(mode ~= "variants");
        for _, control in ipairs({ targetFilter, armourFilter, qualityFilter }) do
            control:SetEnabled(mode == "items"); control:SetVisible(mode ~= "variants");
        end
        variantLevel:SetVisible(mode == "variants"); variantLevelLabel:SetVisible(mode == "variants");
        variantLevel:SetText("");
        query:SetText("");
        searchList:ClearItems();
        previous:SetEnabled(false);
        nextPage:SetEnabled(false);
        searchStatus:SetText(T("Enter a name, numeric ID or item link, then click Find."));
        if (mode == "sets") then
            for _, choice in ipairs({ { "Automatic set membership", false }, { "No equipment set", true } }) do
                local option = choice;
                local control = button(nil, option[1], 0, 0, 600, function()
                    draft.setId, draft.noSet = nil, option[2];
                    setAssignment:SetText(T("Set: ") .. T(option[1]));
                    editorConfirmed:SetChecked(false);
                    search:SetVisible(false);
                end);
                searchList:AddItem(control);
            end
            searchStatus:SetText(T("Choose automatic/no set, or search a set name to assign membership manually."));
        end
        if (mode == "variants") then
            query:SetText(draft.name);
            searchItems();
        end
        search:SetVisible(true);
        search:Activate();
    end
    searchItem = button(editor, "Search item", 22, 140, 150, function() openSearch("items"); end);
    searchPiece = button(editor, "Find set piece", 182, 140, 150, function() openSearch("pieces"); end);
    setAssignment = button(editor, "Set: Automatic", 342, 140, 313, function() openSearch("sets"); end);
    local function addBonus(kind)
        local target = draft;
        local targetState = state;
        local side = editingSide;
        local level = context.level;
        draft.addedConsumables = draft.addedConsumables or {};
        if (bonusWindow) then bonusWindow:SetVisible(false); end
        bonusWindow = StatCapsCompanion.OpenBonuses(kind, level, function(values, count, candidate)
            if (draft ~= target or state ~= targetState or editingSide ~= side
                or not editor:IsVisible() or context.level ~= level) then
                return nil, "The target item changed. Open its bonus picker again.";
            end
            if (kind == "consumable" and draft.addedConsumables[candidate.id]) then
                return nil, "This consumable was already added in this editor. Remove duplicate bonuses manually before adding it again.";
            end
            local current, err = editorValues();
            if (not current) then return nil, err; end
            local sum;
            sum, err = StatCapsCompanion.AddBonuses(current, values, count);
            if (not sum) then return nil, err; end
            for key, input in pairs(editorEntries) do input:SetText(sum[key] and tostring(sum[key]) or ""); end
            if (kind == "consumable") then draft.addedConsumables[candidate.id] = true; end
            editorConfirmed:SetChecked(false);
            editorStatus:SetText(T("Bonuses added to the fields. Check for duplicates, then Apply."));
            return true;
        end);
    end
    button(editor, "Add essence", 22, 510, 180, function() addBonus("essence"); end);
    consumableButton = button(editor, "Add consumable", 212, 140, 220, function() addBonus("consumable"); end);
    local itemSourcesButton = button(editor, "Item sources", 475, 510, 180, function()
        if (sourcesWindow) then sourcesWindow:SetVisible(false); end
        sourcesWindow = StatCapsCompanion.OpenSources(draft.id, draft.name);
    end);

    openEditor = function(side, slot, candidate)
        if (not context or not state) then return; end
        editingSide, editingSlot = side, slot;
        local extra = side == "extraOld" or side == "extraNew";
        if (bonusWindow) then bonusWindow:SetVisible(false); end
        if (sourcesWindow) then sourcesWindow:SetVisible(false); end
        if (extra) then
            draft = { name = T(side == "extraOld" and "Current set/essence bonuses" or "Planned set/essence bonuses"),
                values = state[side], confirmed = state.extrasConfirmed };
        else
            local source;
            if (side == "original") then source = state.original[slot[1]];
            else source = state.replacements[slot[1]] or state.original[slot[1]]; end
            draft = StatCapsLoadouts.CopyItem(candidate or source);
            if (not draft or draft.removed) then
                draft = { name = "", slot = slot[3], confirmed = false };
            end
        end
        editor:SetText(T("Stat Caps - ") .. (extra and draft.name
            or (T(side == "original" and "Equipped" or "Planned") .. " / " .. T(slot[2]))));
        itemName:SetEnabled(not extra and side ~= "original");
        itemLevel:SetEnabled(not extra);
        searchItem:SetEnabled(not extra);
        searchPiece:SetEnabled(not extra);
        setAssignment:SetEnabled(not extra);
        setOnly:SetEnabled(not extra and not candidate and slot ~= nil
            and (side == "original" and state.original[slot[1]] or state.replacements[slot[1]]) ~= nil);
        editorEntries.WeaponDPS:SetEnabled(not extra);
        for _, control in ipairs({ itemName, nameLabel, itemLevel, levelLabel, identity,
            searchItem, searchPiece, setAssignment, setOnly }) do
            control:SetVisible(not extra);
        end
        setAssignment:SetVisible(not extra and not state.manualSetTotals);
        setOnly:SetVisible(not extra and not state.manualSetTotals);
        extrasHelp:SetVisible(extra);
        consumableButton:SetVisible(extra);
        itemSourcesButton:SetVisible(not extra);
        itemSourcesButton:SetEnabled(not extra and draft.id ~= nil);
        if (extra) then
            extrasHelp:SetText(T("Include consumables on both sides: Current contains only buffs already in the snapshot; Planned contains their intended replacement. Unchanged buffs go on both sides or neither.\nSets: ")
                .. T(state.manualSetTotals and "Enter complete set totals; automatic sets are disabled."
                    or "Add only bonuses missing from automatic sets."));
        end
        editorHelp:SetText(T(extra
            and "Flat set, essence and consumable bonuses only, not item stats or character totals. Verify stacking and duration yourself. Percentages, procs and skill effects are not compared."
            or "Enter item bonuses only, not character totals.\nEssences go here or in Set/Essence bonuses, not both. Percentages and procs are not flat ratings."));
        fillEditor();
        editorStatus:SetText(T(extra and (state.manualSetTotals
            and "Manual set totals replace all automatic set bonuses."
            or "Add only missing/manual set bonuses. Do not duplicate the automatic numeric bonuses.")
            or "Enter the tooltip bonuses, then Apply. No extra confirmation is needed."));
        editor:SetVisible(true);
        editor:Activate();
        if (not extra and not draft.id and draft.name ~= ""
            and (not draft.values or (not state.manualSetTotals and not draft.noSet and not draft.setId))) then
            local _, _, _, variants = StatCapsItemDatabase.Lookup(nil, {
                GetName = function() return draft.name; end,
                GetCategory = function() return draft.category; end
            }, context.level);
            if (variants) then
                local matching = {};
                for _, variant in ipairs(variants) do
                    if (StatCapsLoadouts.SlotFits(slot[3], variant.slot)) then matching[#matching + 1] = variant; end
                end
                if (#matching > 0) then openSearch("variants", matching); end
            end
        end
    end
    button(editor, "Cancel", 320, 550, 150, function()
        resumeCalculation = false;
        if (bonusWindow) then bonusWindow:SetVisible(false); end
        if (sourcesWindow) then sourcesWindow:SetVisible(false); end
        editor:SetVisible(false); search:SetVisible(false);
        if (resumeSetReview) then resumeSetReview = false; openSetPrompt(); end
    end);
    setOnly = button(editor, "Apply set only", 22, 550, 175, function()
        local destination = editingSide == "original" and state.original or state.replacements;
        local existing = editingSlot and destination[editingSlot[1]];
        if (not existing or existing.removed or existing.name ~= draft.name
            or (existing.category and existing.category ~= draft.category)) then
            editorStatus:SetText(T("Apply the item first, or keep the equipped item's identity."));
            return;
        end
        existing.setId, existing.noSet = draft.setId, draft.noSet;
        existing.id = draft.id;
        local saved = changed();
        editor:SetVisible(false);
        search:SetVisible(false);
        renderGear();
        if (setsWindow:IsVisible()) then renderSets(); end
        if (resumeCalculation) then resumeCalculation = false; if (saved) then calculate(); end end
    end);
    applyEditor = function()
        if (editingSide ~= "extraOld" and editingSide ~= "extraNew" and not draft.values) then
            local hasInput = false;
            for _, input in pairs(editorEntries) do
                if (input:GetText():find("%S")) then hasInput = true; break; end
            end
            if (not hasInput) then
                editorStatus:SetText(T("Item bonuses are unknown. Choose the matching variant or enter the tooltip bonuses; blank values cannot confirm this item as zero."));
                return;
            end
        end
        local values, err = editorValues();
        if (not values) then editorStatus:SetText(T(err)); return; end
        local extra = editingSide == "extraOld" or editingSide == "extraNew";
        if (extra) then
            if (values.WeaponDPS) then editorStatus:SetText(T("Set bonuses cannot be entered as weapon DPS.")); return; end
            state[editingSide] = values;
            state.extrasConfirmed = false;
            state[editingSide .. "Confirmed"] = true;
        else
            local name = itemName:GetText():match("^%s*(.-)%s*$");
            if (name == "") then editorStatus:SetText(T("Enter the item name.")); return; end
            local levelText = itemLevel:GetText():match("^%s*(.-)%s*$");
            local level = levelText ~= "" and tonumber(levelText) or nil;
            if (levelText ~= "" and (not level or level % 1 ~= 0 or level < 1 or level > 999)) then
                editorStatus:SetText(T("Enter a whole item level from 1 to 999, or leave it blank."));
                return;
            end
            draft.name, draft.values, draft.itemLevel, draft.confirmed = name, values, level, true;
            draft.reviewed, draft.suggested = editingSide == "original", false;
            if (draft.characterLevel and draft.characterLevel ~= context.level) then
                editorStatus:SetText(T("Character level changed. Search this scaling item again and verify its bonuses."));
                return;
            end
            local destination = editingSide == "original" and state.original or state.replacements;
            destination[editingSlot[1]] = StatCapsLoadouts.CopyItem(draft);
            if (editingSide ~= "original" and draft.restrictions and draft.restrictions.precludedSlot == "OFF_HAND") then
                state.replacements.SecondaryWeapon = { removed = true, confirmed = true, name = "", slot = "OFF_HAND" };
            end
        end
        local saved = changed();
        editor:SetVisible(false);
        search:SetVisible(false);
        renderGear();
        if (setsWindow:IsVisible()) then renderSets(); end
        if (resumeSetReview) then
            resumeSetReview = false;
            if (saved) then openSetPrompt(); end
        elseif (resumeCalculation) then resumeCalculation = false; if (saved) then calculate(); end end
    end
    button(editor, "Apply", 485, 550, 170, applyEditor);

    local function dropped(slot, args)
        if (not context or not state) then return; end
        local drag = args and args.DragDropInfo;
        if (not drag) then return; end
        drag:SetSuccessful(false);
        local ok, info, data = pcall(function()
            local shortcut = drag:GetShortcut();
            if (not shortcut or shortcut:GetType() ~= Turbine.UI.Lotro.ShortcutType.Item) then
                error("Drop an item shortcut.");
            end
            local item = shortcut:GetItem();
            if (not item) then error("Cannot read the dropped item."); end
            return item:GetItemInfo(), shortcut:GetData();
        end);
        if (not ok) then status:SetText(T("Item drop failed: ") .. tostring(info)); return; end
        local values, message, equipmentSlot, variants, characterLevel, id, level, restrictions =
            StatCapsItemDatabase.Lookup(data, info, context.level);
        if (equipmentSlot and not StatCapsLoadouts.SlotFits(slot[3], equipmentSlot)) then
            status:SetText(T("Item does not fit the selected equipment slot: ") .. T(slot[2]));
            return;
        end
        selectedSlot = slot;
        local candidate = { name = info:GetName(), category = info:GetCategory(),
            slot = slot[3], values = values, characterLevel = characterLevel,
            id = id, itemLevel = level, restrictions = restrictions,
            icon = type(info.GetIconImageID) == "function" and info:GetIconImageID() or nil,
            iconLayers = StatCapsLoadouts.IconLayers(info) };
        state.replacements[slot[1]] = StatCapsLoadouts.CopyItem(candidate);
        if (restrictions and restrictions.precludedSlot == "OFF_HAND") then
            state.replacements.SecondaryWeapon = { removed = true, confirmed = true, name = "", slot = "OFF_HAND" };
        end
        resumeCalculation, resumeSetReview = false, false;
        local saved = changed();
        renderGear();
        if (variants) then
            openEditor("planned", slot, candidate);
        elseif (saved and not values) then
            status:SetText(T(message));
        end
        drag:SetSuccessful(true);
    end

    local layout = {
        { "Necklace", "Earring1", "Earring2", "Bracelet1", "Bracelet2", "Ring1", "Ring2", "Pocket" },
        { "Head", "Shoulder", "Back", "Chest", "Gloves", "Legs", "Boots", "Class" }
    };
    local positions = {};
    for column, keys in ipairs(layout) do
        for row, key in ipairs(keys) do positions[key] = { (column - 1) * 370, (row - 1) * 38, 346, 36 }; end
    end
    for index, key in ipairs({ "PrimaryWeapon", "SecondaryWeapon", "RangedWeapon" }) do
        positions[key] = { (index - 1) * 240, 310, 236, 66 };
    end
    for _, definition in ipairs(StatCapsLoadouts.Slots) do
        local slot = definition;
        local position = positions[slot[1]];
        local width = (position[3] - 8) / 2;
        local pair = {};
        win.gearSlots[slot[1]] = pair;
        for _, side in ipairs({ "original", "planned" }) do
            local itemSide = side;
            -- Theme textures are shorter than slot cells and item icons have alpha, so back each slot solidly.
            local underlay = Turbine.UI.Control();
            underlay:SetParent(gearPanel);
            underlay:SetPosition(position[1] + (side == "planned" and width + 8 or 0), position[2]);
            underlay:SetSize(width, position[4]);
            underlay:SetBackColor(Turbine.UI.Color(0.055, 0.065, 0.075));
            underlay:SetMouseVisible(false);
            local cell = button(gearPanel, "", position[1] + (side == "planned" and width + 8 or 0),
                position[2], width, function()
                    if (not state) then return; end
                    selectedSlot = slot;
                    resumeCalculation, resumeSetReview = false, false;
                    openEditor(itemSide, slot);
                end);
            cell:SetSize(width, position[4]);
            cell:SetAllowDrop(side == "planned");
            if (side == "planned") then cell.DragDrop = function(_, args) dropped(slot, args); end end
            cell.MouseDoubleClick = function() selectedSlot = slot; openEditor(itemSide, slot); end
            cell.underlay = underlay;
            cell.iconFrame = Turbine.UI.Control();
            cell.iconFrame:SetParent(cell);
            cell.iconFrame:SetPosition(1, 1);
            cell.iconFrame:SetSize(32, 32);
            cell.iconFrame:SetBackColor(Turbine.UI.Color(0.02, 0.025, 0.03));
            cell.iconFrame:SetMouseVisible(false);
            cell.iconLayers = {};
            for index, key in ipairs({ "back", "under", "shadow" }) do
                local layer = Turbine.UI.Control();
                layer:SetParent(cell);
                layer:SetPosition(1, 1);
                layer:SetSize(32, 32);
                layer:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend);
                layer:SetMouseVisible(false);
                cell.iconLayers[key] = layer;
            end
            cell.icon = label(cell, "", 1, 1, 32, 32, true);
            cell.icon:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
            cell.icon:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend);
            cell.title = label(cell, "", 36, 0, width - 38, 14, true);
            cell.name = label(cell, "", 36, 14, width - 38, position[4] - 14, true);
            cell.title:SetFont(Turbine.UI.Lotro.Font.Verdana12);
            cell.name:SetFont(Turbine.UI.Lotro.Font.Verdana12);
            for _, text in ipairs({ cell.icon, cell.title, cell.name }) do text:SetMouseVisible(false); end
            pair[side] = cell;
        end
    end
    renderGear = function()
        local missing = 0;
        win.missingItems = {};
        for _, slot in ipairs(StatCapsLoadouts.Slots) do
            for _, side in ipairs({ "original", "planned" }) do
                local cell = win.gearSlots[slot[1]][side];
                local item;
                if (side == "original") then item = state.original[slot[1]];
                else item = state.replacements[slot[1]]; end
                local needsValues = item and not item.removed and not item.values;
                local colour = needsValues and Turbine.UI.Color(1, 0.55, 0.45)
                    or Turbine.UI.Color(0.92, 0.9, 0.84);
                cell.title:SetForeColor(colour);
                cell.title:SetText((needsValues and "! " or "") .. T(slot[2]));
                cell.name:SetText(item and (item.removed and T("Unequipped") or item.name)
                    or T(side == "planned" and "Keep equipped" or "Empty slot"));
                local layers = item and not item.removed and item.icon and item.iconLayers or {};
                for key, layer in pairs(cell.iconLayers) do layer:SetBackground(layers[key]); end
                cell.icon:SetBackground(item and item.icon or nil);
                cell.icon:SetText(item and item.icon and "" or (side == "planned" and "+" or "-"));
                if (needsValues) then
                    missing = missing + 1;
                    win.missingItems[#win.missingItems + 1] = { slot = slot[1], side = side, name = item.name };
                end
            end
        end
        missingLabel:SetText(T("Missing values: ") .. missing .. " / " .. T("Unchanged items cancel out."));
        missingLabel:SetForeColor(missing > 0 and Turbine.UI.Color(1, 0.55, 0.45) or Turbine.UI.Color(0.92, 0.9, 0.84));
        local pending = 0;
        for key in pairs(state.replacements) do
            for _, item in pairs({ old = state.original[key], new = state.replacements[key] }) do
                if (not item.removed and not item.values) then pending = pending + 1; end
            end
        end
        selectedLabel:SetText(T("Selected slot: ") .. T(selectedSlot[2]) .. " / "
            .. T("Missing changed-item values: ") .. pending);
    end
    button(win, "Edit equipped", 22, 552, 168, function() openEditor("original", selectedSlot); end);
    button(win, "Edit planned", 203, 552, 168, function() openEditor("planned", selectedSlot); end);
    button(win, "Keep equipped", 384, 552, 168, function()
        if (not state) then return; end
        state.replacements[selectedSlot[1]] = nil; changed(); renderGear();
    end);
    button(win, "Unequip planned", 565, 552, 173, function()
        if (not state) then return; end
        state.replacements[selectedSlot[1]] = { removed = true, confirmed = true, name = "", slot = selectedSlot[3] };
        changed(); renderGear();
    end);

    local setsList = list(setsWindow, 22, 112, 633, 272);
    local setsStatus = label(setsWindow, "", 22, 390, 633, 60);
    local extraChecked = Turbine.UI.Lotro.CheckBox();
    extraChecked:SetParent(setsWindow);
    extraChecked:SetPosition(22, 500);
    extraChecked:SetSize(435, 28);
    extraChecked:SetText(T("Current and planned manual set additions verified"));
    extraChecked:SetVisible(false);
    extraChecked.CheckedChanged = function()
        if (state) then state.extrasConfirmed = extraChecked:IsChecked(); report:SetVisible(false); end
    end
    label(setsWindow, "Current and planned set totals are entered manually.\nOnly flat numeric bonuses are included in the comparison.", 22, 43, 633, 52);
    button(setsWindow, "Current set/essence bonuses", 22, 459, 300, function() openEditor("extraOld"); end);
    button(setsWindow, "Planned set/essence bonuses", 337, 459, 318, function() openEditor("extraNew"); end);
    button(setsWindow, "Compare loadout", 470, 500, 185, function()
        state.setsConfirmed = true;
        setsChecked:SetChecked(true);
        setsWindow:SetVisible(false);
        calculate();
    end);
    renderSets = function()
        setsList:ClearItems();
        if (state.manualSetTotals) then
            addText(setsList, "Manual set totals replace all automatic set bonuses.", 610);
            addText(setsList, T("Current set/essence bonuses") .. ": " .. valuesText(state.extraOld), 610, true);
            addText(setsList, T("Planned set/essence bonuses") .. ": " .. valuesText(state.extraNew), 610, true);
            setsStatus:SetText(T("No per-item set assignment is needed in manual totals mode. Verify the current and planned totals, including zero when no set is active."));
            extraChecked:SetChecked(StatCapsLoadouts.ExtrasVerified(state));
            return;
        end
        local planned = StatCapsLoadouts.Planned(state);
        local before, beforeError = StatCapsSetDatabase.Calculate(state.original, context.level, state.manualSets);
        local after, afterError = StatCapsSetDatabase.Calculate(planned, context.level, state.manualSets);
        local ids = {};
        for _, equipment in ipairs({ state.original, planned }) do
            for _, item in pairs(equipment) do
                local memberships, err = StatCapsSetDatabase.Resolve(item);
                if (not memberships) then setsStatus:SetText(T(err)); return; end
                for _, id in ipairs(memberships) do ids[id] = true; end
            end
        end
        local sorted = {};
        for id in pairs(ids) do sorted[#sorted + 1] = id; end
        table.sort(sorted);
        for _, id in ipairs(sorted) do
            local setId = id;
            local row = button(nil, (state.manualSets[id] and T("Manual: ") or T("Automatic: "))
                .. StatCapsSetRecords[id].name, 0, 0, 610, function()
                state.manualSets[setId] = not state.manualSets[setId] or nil;
                state.extrasConfirmed = false;
                state.extraOldConfirmed, state.extraNewConfirmed = false, false;
                extraChecked:SetChecked(false);
                changed();
                renderSets();
            end, true);
            row:SetSize(610, 40);
            setsList:AddItem(row);
            for _, side in ipairs({ { "Equipped", before }, { "Planned", after } }) do
                if (side[2]) then
                    for _, bonus in ipairs(side[2].rows) do
                        if (bonus.id == id) then
                            addText(setsList, T(side[1]) .. ": " .. bonus.count .. "/" .. bonus.threshold .. " / "
                                .. T(bonus.active and "Active" or "Inactive") .. " / " .. valuesText(bonus.values), 610, true);
                            if (bonus.active) then
                                for _, warning in ipairs(bonus.warnings) do
                                    addText(setsList, T("Not scored: ") .. warning, 610);
                                end
                            end
                        end
                    end
                end
            end
        end
        local unknown = (before and #before.unknown or 0) + (after and #after.unknown or 0);
        for _, side in ipairs({ { "Equipped", before }, { "Planned", after } }) do
            for _, name in ipairs(side[2] and side[2].unknown or {}) do
                addText(setsList, T(side[1]) .. " / " .. T("Unknown set: ") .. name, 610, true);
            end
        end
        setsStatus:SetText(T(beforeError or afterError or (unknown > 0
            and "Some item set memberships are unknown. Assign their set in the item editor, or explicitly choose No equipment set."
            or "Verify set membership, thresholds and manual additions, then tick Set bonuses checked in the planner.")));
        if (#sorted == 0 and before and after) then
            addText(setsList, "No automatic equipment sets detected. Manual set additions are available below.", 610);
        end
        addText(setsList, T("Current manual set additions") .. ": " .. valuesText(state.extraOld), 610, true);
        addText(setsList, T("Planned manual set additions") .. ": " .. valuesText(state.extraNew), 610, true);
        extraChecked:SetChecked(StatCapsLoadouts.ExtrasVerified(state));
    end
    button(win, "Review set bonuses", 498, 585, 240, function()
        if (not state) then return; end
        renderSets(); setsWindow:SetVisible(true); setsWindow:Activate();
    end);
    button(win, "Current set/essence bonuses", 22, 585, 225, function()
        if (state) then resumeCalculation = false; openEditor("extraOld"); end
    end);
    button(win, "Planned set/essence bonuses", 258, 585, 225, function()
        if (state) then resumeCalculation = false; openEditor("extraNew"); end
    end);
    local manualTotals = Turbine.UI.Lotro.CheckBox();
    manualTotals:SetParent(win);
    manualTotals:SetPosition(218, 584);
    manualTotals:SetSize(270, 22);
    manualTotals:SetText(T("Manual set totals"));
    manualTotals:SetVisible(false);
    setsChecked:SetVisible(false);
    manualTotals.CheckedChanged = function()
        if (not state or state.manualSetTotals == manualTotals:IsChecked()) then return; end
        state.manualSetTotals = manualTotals:IsChecked();
        setsChecked:SetVisible(false);
        state.extrasConfirmed = false;
        state.extraOldConfirmed, state.extraNewConfirmed = false, false;
        local saved = changed();
        if (saved) then status:SetText(T(state.manualSetTotals
            and "Manual totals enabled. Enter Current set bonuses and Planned set bonuses; no per-item set assignment is needed."
            or "Automatic set bonuses enabled. Manual entries are additional bonuses only.")); end
        if (setsWindow:IsVisible()) then renderSets(); end
    end
    setsChecked.CheckedChanged = function()
        if (state) then state.setsConfirmed = setsChecked:IsChecked(); report:SetVisible(false); end
    end
    local verdict = label(report, "", 22, 43, 716, 38);
    verdict:SetFont(Turbine.UI.Lotro.Font.Verdana18);
    label(report, "Combined stat score includes numeric set bonuses and cap clipping.\nWeapon DPS is separate. Procs, skill modifiers and percentage set effects are not predicted damage.", 22, 84, 716, 46);
    local reportList = list(report, 22, 139, 716, 448);
    label(report, "This is a combined numeric-stat estimate, not a full damage or set-effect simulation.", 22, 599, 716, 30);
    local setSummary = list(setPrompt, 22, 116, 566, 104);
    label(setPrompt, "Add set or essence bonuses before comparing?\nEnter complete current and planned flat totals, not item stats.", 22, 43, 566, 30);
    label(setPrompt, "Compare uses the totals shown, including zero. No automatic sets are added.", 22, 223, 566, 44);
    openSetPrompt = function()
        if (not state) then return; end
        win.lastResult = nil;
        resumeCalculation, resumeSetReview = false, false;
        if (not state.manualSetTotals) then
            state.manualSetTotals = true;
            state.extraOldConfirmed, state.extraNewConfirmed, state.extrasConfirmed = false, false, false;
            if (not changed()) then return; end
        end
        setSummary:ClearItems();
        addText(setSummary, T("Current set/essence bonuses") .. ": " .. valuesText(state.extraOld), 540, true);
        addText(setSummary, T("Planned set/essence bonuses") .. ": " .. valuesText(state.extraNew), 540, true);
        report:SetVisible(false);
        setPrompt:SetVisible(true);
        setPrompt:Activate();
    end
    for _, option in ipairs({
        { "Current set/essence bonuses", "extraOld", 22 }, { "Planned set/essence bonuses", "extraNew", 310 }
    }) do
        local side = option[2];
        button(setPrompt, option[1], option[3], 78, 278, function()
            resumeSetReview = true;
            setPrompt:SetVisible(false);
            openEditor(side);
        end);
    end
    button(setPrompt, "Cancel", 22, 283, 160, function() setPrompt:SetVisible(false); end);
    button(setPrompt, "Compare now", 408, 283, 180, function()
        state.extraOldConfirmed, state.extraNewConfirmed = true, true;
        state.extrasConfirmed = false;
        setPrompt:SetVisible(false);
        calculate();
    end);
    calculate = function()
        if (not state) then return; end
        win.lastResult = nil;
        local fresh, err = getContext(selectedTarget);
        if (not fresh) then status:SetText(T(err)); report:SetVisible(false); return; end
        if (fresh.level ~= context.level) then
            status:SetText(T("Character level changed. Refresh equipment and verify the plan again."));
            report:SetVisible(false);
            return;
        end
        local equipment;
        equipment, err = StatCapsLoadouts.Equipment(fresh.equipment);
        if (not equipment) then status:SetText(T(err)); report:SetVisible(false); return; end
        if (not sameEquipment(state.source, equipment)) then
            status:SetText(T("Equipment changed. Refresh equipment and verify the plan again."));
            report:SetVisible(false);
            return;
        end
        context = fresh;
        for _, definition in ipairs(StatCapsLoadouts.Slots) do
            if (state.replacements[definition[1]]) then
                for _, side in ipairs({ "original", "replacements" }) do
                    local item = state[side][definition[1]];
                    if (item and not item.removed and not item.values) then
                        resumeCalculation = true;
                        report:SetVisible(false);
                        openEditor(side == "original" and "original" or "planned", definition);
                        status:SetText(T("Complete the highlighted item and Apply. Comparison continues automatically."));
                        return;
                    end
                end
            end
        end
        for _, definition in ipairs(StatCapsLoadouts.Slots) do
            for _, side in ipairs({ "original", "replacements" }) do
                local item = state[side][definition[1]];
                if (not state.manualSetTotals and item and not item.removed and not item.id
                    and ((state.replacements[definition[1]] and not item.confirmed)
                        or (not item.noSet and not item.setId))) then
                    local _, _, _, variants = StatCapsItemDatabase.Lookup(nil, {
                        GetName = function() return item.name; end,
                        GetCategory = function() return item.category; end
                    }, context.level);
                    if (variants) then
                        resumeCalculation = true;
                        report:SetVisible(false);
                        openEditor(side == "original" and "original" or "planned", definition);
                        status:SetText(T("Choose the matching equipped variant, verify its bonuses, then Apply to continue the loadout comparison."));
                        return;
                    end
                end
            end
        end
        if (not StatCapsLoadouts.ExtrasVerified(state)) then
            for _, side in ipairs({ "extraOld", "extraNew" }) do
                if (not state[side .. "Confirmed"] and (state.manualSetTotals or next(state.manualSets) ~= nil
                    or StatCapsLoadouts.HasBonuses(state[side]))) then
                    resumeCalculation = true;
                    openEditor(side);
                    status:SetText(T("Apply the current and planned set/essence bonuses to continue. Zero is valid when none are active."));
                    return;
                end
            end
        end
        state.setsConfirmed = setsChecked:IsChecked();
        local result;
        result, err = StatCapsLoadouts.Evaluate(CalcStat, context, state);
        if (not result) then
            status:SetText(T(err));
            report:SetVisible(false);
            if (err:find("Set membership is unknown", 1, true)
                or err:find("Set bonuses checked", 1, true)) then
                renderSets(); setsWindow:SetVisible(true); setsWindow:Activate();
            end
            return;
        end
        if (virtueConfirm:IsChecked()) then
            if (confirmedVirtueSignature and confirmedVirtueSignature ~= virtueSignature(context)) then
                result.virtueError = "Saved virtues or ranks changed. Review them, then confirm again.";
                virtueConfirm:SetChecked(false);
                confirmedVirtueSignature = nil;
            else
                result.virtues, result.virtueError = StatCapsLoadouts.CompareVirtues(CalcStat, context, result);
            end
        end
        reportList:ClearItems();
        verdict:SetText(T(result.score and (StatCapsScoring.ScoreState(result.score) .. " / Stats only: ")
            or "Score unavailable: ") .. (result.score and StatCapsScoring.FormatScore(result.score)
            or T(result.scoreError)));
        addText(reportList, T("Changed equipment slots: ") .. result.changes, 693);
        if (result.virtues) then
            local adjusted = result.virtues;
            addText(reportList, T("Gear only: ") .. StatCapsScoring.FormatScore(result.score), 693, true);
            addText(reportList, T("Gear + virtue swaps: ") .. T(StatCapsScoring.ScoreState(adjusted.total))
                .. " / " .. StatCapsScoring.FormatScore(adjusted.total), 693, true);
            addText(reportList, T("With both loadouts' virtues optimized: ")
                .. StatCapsScoring.FormatScore(adjusted.optimizedDelta), 693, true);
            local function names(choices)
                local values = {};
                for _, choice in pairs(choices) do values[#values + 1] = T(choice.name) .. " " .. choice.rank; end
                table.sort(values);
                return #values > 0 and table.concat(values, ", ") or T("None");
            end
            addText(reportList, T("Current virtues: ") .. names(adjusted.planned.selection), 693, true);
            addText(reportList, T("Suggested planned virtues: ") .. names(adjusted.planned.choices), 693, true);
            addText(reportList, T("Best virtues with current gear: ") .. names(adjusted.current.choices), 693, true);
        elseif (result.virtueError) then
            addText(reportList, T("Virtue-adjusted comparison unavailable: ") .. T(result.virtueError), 693, true);
        else
            addText(reportList, "Virtue swaps not included. Confirm the saved virtues and ranks to include them.", 693);
        end
        for _, weapon in ipairs(result.weapons) do addText(reportList, T(weapon.slot) .. " / " .. weapon.text, 693); end
        local keys = {};
        for key in pairs(context.snapshot.samples) do keys[#keys + 1] = key; end
        table.sort(keys);
        for _, key in ipairs(keys) do
            local old, new = context.snapshot.samples[key], result.projected.samples[key];
            if (old.valid and new.valid and type(old.rating) == "number"
                and type(new.rating) == "number" and type(old.limit) == "number") then
                addText(reportList, T(old.label) .. ": " .. string.format("%.0f -> %.0f / cap %.0f / %+.0f",
                    old.rating, new.rating, old.limit, new.rating - old.rating), 693);
            else
                addText(reportList, T(old.label) .. ": " .. T("Unavailable"), 693);
            end
        end
        for _, field in ipairs({ "Might", "Agility", "Vitality", "Will", "Fate" }) do
            local old, new = context.snapshot.attributes[field], result.projected.attributes[field];
            if (old ~= nil and new ~= nil) then
                addText(reportList, T(field) .. ": " .. string.format("%.0f -> %.0f", old, new), 693);
            end
        end
        for _, field in ipairs({ { "Max Morale", "morale" }, { "Armour", "armour" } }) do
            local old, new = context.snapshot[field[2]], result.projected[field[2]];
            if (old ~= nil and new ~= nil) then
                addText(reportList, T(field[1]) .. ": " .. string.format("%.0f -> %.0f", old, new), 693);
            end
        end
        if (result.hope ~= 0) then addText(reportList, T("Unscored Hope change: ") .. result.hope, 693); end
        addText(reportList, state.manualSetTotals
            and "Manual set totals replace all automatic set bonuses." or "Manual additions are added to automatic set bonuses.", 693);
        addText(reportList, T(state.manualSetTotals and "Current set/essence bonuses" or "Current manual set additions")
            .. ": " .. valuesText(state.extraOld), 693, true);
        addText(reportList, T(state.manualSetTotals and "Planned set/essence bonuses" or "Planned manual set additions")
            .. ": " .. valuesText(state.extraNew), 693, true);
        for _, side in ipairs({ { "Equipped set bonuses", result.oldSets }, { "Planned set/essence bonuses", result.newSets } }) do
            addText(reportList, side[1], 693);
            for _, bonus in ipairs(side[2].rows) do
                if (bonus.active) then
                    addText(reportList, bonus.name .. " / " .. bonus.threshold .. ": " .. valuesText(bonus.values), 693, true);
                    for _, warning in ipairs(bonus.warnings) do
                        addText(reportList, bonus.name .. " / " .. T("Not scored: ") .. T(warning), 693, true);
                    end
                end
            end
        end
        for _, detail in ipairs(result.details) do
            addText(reportList, T(detail.label) .. " / " .. T("Useful change: ") ..
                string.format("%+.0f", detail.useful) .. " / " .. StatCapsScoring.FormatScore(detail.points), 693);
        end
        report:SetVisible(true);
        report:Activate();
        status:SetText(T("Loadout calculated. Review the result and unscored effects."));
        win.lastResult = result;
    end
    button(win, "Compare", 192, 632, 180, openSetPrompt);
    button(win, "Save plan", 22, 632, 155, function()
        if (not state) then return; end
        local key = targetKey();
        if (not key or not savePlan) then status:SetText(T("Saving loadout plans is unavailable.")); return; end
        local data = StatCapsLoadouts.Serialize(state);
        local ok, err = savePlan(key, data);
        if (not ok) then status:SetText(T(err)); return; end
        plans[key] = data;
        status:SetText(T("Loadout plan saved. Recheck bonuses when restoring it."));
    end);
    button(win, "Reset plan", 388, 632, 155, function()
        if (not context) then return; end
        local reset, err = StatCapsLoadouts.New(context.equipment);
        if (not reset) then status:SetText(T(err)); return; end
        state = reset;
        win.HideChildren();
        state.manualSetTotals = true;
        win.state = state;
        manualTotals:SetChecked(state.manualSetTotals);
        setsChecked:SetVisible(false);
        changed(); renderGear();
    end);
    button(win, "Best gear (Test)", 558, 632, 180, function()
        if (bestGearWindow) then bestGearWindow.CloseChildren(); bestGearWindow:SetVisible(false); end
        bestGearWindow = StatCapsBestGearWindow.Open(function()
            if (not context or not state) then return nil, nil, "Refresh the planner's character first."; end
            local fresh, err = getContext(selectedTarget);
            if (not fresh) then return nil, nil, err; end
            local source, equipmentError = StatCapsLoadouts.Equipment(fresh.equipment);
            if (not source) then return nil, nil, equipmentError; end
            if (fresh.level ~= context.level or not sameEquipment(state.source, source)) then
                return nil, nil, "Equipment or character level changed. Refresh equipment and review the current bonuses first.";
            end
            return fresh, state;
        end);
    end);

    local function chooseTarget(key)
        resumeCalculation = false;
        resumeSetReview = false;
        virtueConfirm:SetChecked(false);
        confirmedVirtueSignature = nil;
        if (state and targetKey()) then
            plans[targetKey()] = StatCapsLoadouts.Serialize(state);
            activePlans[targetKey()] = { state = state, level = context.level };
        end
        local fresh, err = getContext(key);
        if (not fresh or not fresh.equipment) then
            status:SetText(T(err or "Equipment snapshot is unavailable. Load StatCaps on that character once."));
            return;
        end
        local identityKey = key or fresh.characterName;
        local saved = identityKey and (plans[identityKey] or (getPlan and getPlan(identityKey)));
        local restored;
        restored, err = StatCapsLoadouts.New(fresh.equipment, saved);
        if (not restored) then
            selectedTarget, context, state = key, fresh, nil;
            win.state = nil;
            gearPanel:SetVisible(false);
            win.HideChildren();
            targetButton:SetText(key and (T("Target: ") .. fresh.characterName) or T("Target: This character"));
            status:SetText(T(err) .. " " .. T("Use Reset plan to start again."));
            return;
        end
        local cached = identityKey and activePlans[identityKey];
        if (cached and cached.level == fresh.level and sameEquipment(cached.state.source, restored.source)) then
            restored = cached.state;
        end
        restored.manualSetTotals = true;
        selectedTarget, context, state = key, fresh, restored;
        gearPanel:SetVisible(true);
        win.state = state;
        manualTotals:SetChecked(state.manualSetTotals);
        setsChecked:SetVisible(false);
        win.lastResult = nil;
        targetButton:SetText(key and (T("Target: ") .. context.characterName) or T("Target: This character"));
        win.HideChildren();
        setsChecked:SetChecked(state.setsConfirmed);
        renderGear();
        status:SetText(T("Drop planned replacements; empty slots keep current equipment. Set bonuses are entered manually."));
    end
    local targetList = list(targets, 18, 78, 394, 320);
    label(targets, "Choose which character's equipment and build to use.", 18, 38, 390, 32);
    targetButton = button(win, "Target: This character", 22, 42, 350, function()
        targetList:ClearItems();
        targetList:AddItem(button(nil, "This character - current live stats", 0, 0, 374, function() chooseTarget(nil); end));
        for _, saved in ipairs(getProfiles and getProfiles() or {}) do
            local profile = saved;
            local choice = button(nil, profile.name .. " / " .. T(profile.className) .. " / " .. profile.level,
                0, 0, 374, function() chooseTarget(profile.key); end, true);
            choice:SetSize(374, 42);
            targetList:AddItem(choice);
        end
        targets:SetVisible(true);
        targets:Activate();
    end);
    button(win, "Refresh equipment", 386, 42, 170, function() chooseTarget(selectedTarget); end);
    button(win, "Clear planned gear", 568, 42, 170, function()
        if (not state) then return; end
        resumeCalculation, resumeSetReview = false, false;
        win.HideChildren();
        state.replacements = {};
        local saved = changed();
        renderGear();
        if (saved) then status:SetText(T("Planned gear cleared. All slots keep equipped items. Current bonuses and set/essence totals are unchanged.")); end
    end);
    win.HideChildren = function()
        for _, child in ipairs({ report, editor, search, setsWindow, setPrompt, targets }) do child:SetVisible(false); end
        if (bonusWindow) then bonusWindow:SetVisible(false); end
        if (sourcesWindow) then sourcesWindow:SetVisible(false); end
        if (bestGearWindow) then bestGearWindow.CloseChildren(); bestGearWindow:SetVisible(false); end
    end
    editor.VisibleChanged = function()
        if (not editor:IsVisible()) then
            if (bonusWindow) then bonusWindow:SetVisible(false); end
            if (sourcesWindow) then sourcesWindow:SetVisible(false); end
        end
    end
    local visibilityChanged = win.VisibleChanged;
    win.VisibleChanged = function()
        if (visibilityChanged) then visibilityChanged(); end
        if (not win:IsVisible()) then win.HideChildren(); end
    end
    win.SelectTarget = chooseTarget;
    chooseTarget(initialTarget);
    win:SetVisible(true);
    return win;
end
