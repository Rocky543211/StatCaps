StatCapsBestGearWindow = {};

local function T(text) return StatCapsLocalization.Text(text); end
local function label(parent, text, x, y, width, height)
    local item = Turbine.UI.Label();
    item:SetParent(parent); item:SetPosition(x, y); item:SetSize(width, height);
    item:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    item:SetForeColor(Turbine.UI.Color(0.92, 0.9, 0.84)); item:SetText(T(text));
    return item;
end
local function button(parent, text, x, y, width, handler)
    local item = StatCapsTheme.Button();
    item:SetParent(parent); item:SetPosition(x, y); item:SetSize(width, 26);
    item:SetText(T(text)); item.Click = handler;
    return item;
end
local function checkbox(parent, text, x, y, width)
    local item = Turbine.UI.Lotro.CheckBox();
    item:SetParent(parent); item:SetPosition(x, y); item:SetSize(width, 24);
    item:SetFont(Turbine.UI.Lotro.Font.Verdana12); item:SetText(T(text)); item:SetChecked(false);
    return item;
end
local function list(parent, x, y, width, height)
    local item = Turbine.UI.ListBox();
    item:SetParent(parent); item:SetPosition(x, y); item:SetSize(width - 16, height);
    local scroll = Turbine.UI.Lotro.ScrollBar();
    scroll:SetParent(parent); scroll:SetPosition(x + width - 13, y); scroll:SetSize(12, height);
    scroll:SetOrientation(Turbine.UI.Orientation.Vertical); item:SetVerticalScrollBar(scroll);
    return item;
end
local function textHeight(text, columns)
    local lines = 0;
    for line in (text .. "\n"):gmatch("(.-)\n") do lines = lines + math.max(1, math.ceil(#line / columns)); end
    return lines * 20 + 4;
end
local function valuesText(values)
    local parts = {};
    for _, field in ipairs(StatCapsManual.Fields) do
        if (field[1] ~= "WeaponDPS" and values[field[1]] and values[field[1]] ~= 0) then
            parts[#parts + 1] = T(field[2]) .. " " .. values[field[1]];
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or T("No flat stat bonus");
end

function StatCapsBestGearWindow.Open(getInputs)
    local win = StatCapsTheme.Window();
    win:SetText(T("Stat Caps - Best gear (Local test)")); win:SetSize(760, 750);
    StatCapsTheme.Panel(win, 760, 750);
    local width, height = Turbine.UI.Display.GetSize();
    win:SetPosition(math.max(0, (width - 760) / 2), math.max(0, (height - 750) / 2));
    local options = { excludedIds = {}, excludedNames = {}, itemLevels = {}, pinned = {} };
    local result, job, sourceWindow, inputKey, selected = nil, nil, nil, nil, StatCapsLoadouts.Slots[1];
    local header = label(win, "", 22, 42, 716, 34);
    label(win, "Experimental numeric-stat search, not a guaranteed best or obtainable build. Known rewards use character-to-item-level curves; other items use base levels. Equip minimums stay separate.", 22, 80, 716, 58);
    local confirmed = checkbox(win, "Current gear bonuses, Current extras and equipped virtues match the snapshot.", 22, 140, 716);
    local unverified = checkbox(win, "Include missing minimums / conditional requirements (unverified)", 22, 166, 716);
    local weapons = checkbox(win, "Search weapons/class items: same equipped type, no known DPS loss; procs ignored", 22, 192, 716);
    local unsourced = checkbox(win, "Include items with no known source (often removed or unreleased)", 22, 249, 716);
    label(win, "Current extras are removed; new numeric sets are automatic. Socket bonuses, ongoing buffs and passive virtue ranks are not optimized. Exclude items you cannot obtain.", 22, 275, 716, 54);
    local virtues = label(win, "", 22, 331, 716, 54);
    local slots = list(win, 22, 413, 257, 270);
    local alternatives = list(win, 292, 413, 446, 270);
    local variants = checkbox(win, "Exclusion covers all same-name variants", 292, 387, 446);
    variants:SetChecked(true);
    local status = label(win, "Review current item and set/essence totals in the planner first, then confirm above.", 22, 691, 716, 52);
    local generate, clear, stop;
    local function closeSources()
        if (sourceWindow) then sourceWindow:SetVisible(false); end
    end
    local function cancel()
        job = nil; win:SetWantsUpdates(false); closeSources();
        if (generate) then generate:SetEnabled(true); clear:SetEnabled(true); stop:SetEnabled(false); end
    end
    local function invalidate()
        cancel(); result = nil; win.lastResult = nil; slots:ClearItems(); alternatives:ClearItems(); virtues:SetText("");
        status:SetText(T("Options changed. Generate again; the normal plan is unchanged."));
    end
    local render, start;
    local function displayName(item)
        return item and (item.id and StatCapsCompanion.Name(item.id, item.name) or item.name) or T("Empty slot");
    end
    local function exclusions()
        local count = 0;
        for _ in pairs(options.excludedIds) do count = count + 1; end
        for _ in pairs(options.excludedNames) do count = count + 1; end
        return count;
    end
    render = function()
        slots:ClearItems(); alternatives:ClearItems();
        if (not result) then return; end
        local names, nameError = StatCapsCompanion.Names();
        if (not names) then status:SetText(T(nameError)); return; end
        for _, definition in ipairs(StatCapsLoadouts.Slots) do
            local slot = definition;
            local item = result.equipment[slot[1]];
            local text = T(slot[2]) .. (result.kept[slot[1]] and (" / " .. T("Kept")) or "") .. "\n" .. displayName(item);
            local row = button(nil, text, 0, 0, 235, function() selected = slot; render(); end);
            row:SetSize(235, math.max(70, textHeight(text, 28)));
            if (selected[1] == slot[1]) then row:SetForeColor(StatCapsTheme.Accent()); end
            slots:AddItem(row);
        end
        if (result.kept[selected[1]]) then
            alternatives:AddItem(label(nil, "Kept from your snapshot. Weapon DPS, legendary effects and proficiency are not fully modeled. Enable same-type weapon search only if you want a numeric-stat test.", 0, 0, 420, 110));
            return;
        end
        local candidates = result.alternatives[selected[1]];
        if (#candidates == 0) then
            alternatives:AddItem(label(nil, "No supported eligible alternatives. Missing requirements are excluded unless you explicitly include them.", 0, 0, 420, 90));
            return;
        end
        for _, choice in ipairs(candidates) do
            local item = choice.item;
            local row = Turbine.UI.Control();
            local isChosen = result.equipment[selected[1]] and result.equipment[selected[1]].id == item.id;
            local title = displayName(item) .. (isChosen and (" / " .. T("Chosen")) or "");
            local rule = item.rule or (item.id and StatCapsGearRules[item.id]);
            local minimum = rule and rule[1] > 0 and tostring(rule[1]) or T("Unknown");
            local description = title .. "\n" .. T("Equip minimum: ") .. minimum .. " / " .. T("Item level: ") .. tostring(item.itemLevel or "-")
                .. " / ID " .. tostring(item.id or "-") .. "\n" .. T("Gear + fixed virtues: ")
                .. string.format("%+.2f", choice.score) .. (item.values.WeaponDPS and (" / DPS " .. item.values.WeaponDPS) or "")
                .. "\n" .. valuesText(item.values);
            if (rule and (rule[1] == 0 or rule[6] ~= "")) then
                description = description .. "\n" .. T("Unverified requirements: ") ..
                    (rule[6] ~= "" and rule[6] or T("Minimum equip level missing."));
            end
            if (item.generatedLevel) then
                description = description .. "\n" .. T("Reward generated at character level: ") .. item.generatedAt
                    .. " / " .. T("Item-level range: ") .. item.generatedLevel .. "-" .. item.generatedMaximum
                    .. " / " .. T("Base roll used unless overridden.");
            end
            local y = textHeight(description, 49);
            label(row, description, 0, 0, 420, y);
            row:SetSize(420, y + 76);
            local slotKey = selected[1];
            button(row, "Use + recalculate", 0, y + 2, 132, function()
                if (not item.id or item.current) then status:SetText(T("This is the current item; use the normal planner to edit it.")); return; end
                options.pinned[slotKey] = item.id; start();
            end);
            button(row, "Exclude + retry", 142, y + 2, 132, function()
                if (variants:IsChecked()) then options.excludedNames[item.name] = true;
                elseif (item.id) then options.excludedIds[item.id] = true;
                else status:SetText(T("Choose an exact item ID before excluding it.")); return; end
                for key, id in pairs(options.pinned) do
                    local record = StatCapsItemRecords[id];
                    if (id == item.id or (record and options.excludedNames[record[1]])) then options.pinned[key] = nil; end
                end
                start();
            end);
            local sources = button(row, "Item sources", 284, y + 2, 132, function()
                closeSources(); sourceWindow = StatCapsCompanion.OpenSources(item.id, displayName(item));
            end);
            sources:SetEnabled(item.id ~= nil);
            local record = item.id and StatCapsItemRecords[item.id];
            if (record and record[7] and record[7][4] ~= "character" and not item.current) then
                label(row, "Item level:", 0, y + 34, 95, 24);
                local input = Turbine.UI.Lotro.TextBox();
                input:SetParent(row); input:SetPosition(100, y + 34); input:SetSize(66, 24);
                input:SetMultiline(false); input:SetFont(Turbine.UI.Lotro.Font.Verdana14);
                input:SetText(options.itemLevels[item.id] and tostring(options.itemLevels[item.id]) or "");
                button(row, "Set level + retry", 178, y + 34, 238, function()
                    local raw = input:GetText():match("^%s*(.-)%s*$");
                    local level = raw ~= "" and tonumber(raw) or nil;
                    if (raw ~= "" and (not level or level % 1 ~= 0 or level < 1 or level > 999)) then
                        status:SetText(T("Enter a whole item level from 1 to 999, or leave it blank.")); return;
                    end
                    local values, err = StatCapsItemDatabase.Values(record, level, result.context.level);
                    if (not values) then status:SetText(T(err)); return; end
                    options.itemLevels[item.id] = level;
                    options.pinned[slotKey] = item.id; start();
                end);
            end
            alternatives:AddItem(row);
        end
    end
    start = function()
        cancel(); result = nil; win.lastResult = nil; slots:ClearItems(); alternatives:ClearItems(); virtues:SetText("");
        if (not confirmed:IsChecked()) then status:SetText(T("Confirm the current baseline before searching.")); return; end
        local context, state, err = getInputs();
        if (not context or not state) then status:SetText(T(err or "The target snapshot is unavailable.")); return; end
        options.unverified, options.weapons = unverified:IsChecked(), weapons:IsChecked();
        options.includeUnsourced = unsourced:IsChecked();
        header:SetText(context.characterName .. " / " .. T(context.className) .. " / " .. T("Level ")
            .. context.level .. " / " .. T(context.profile.name));
        local limit, limitError = StatCapsVirtues.Limits(context.level);
        if (not limit) then status:SetText(T(limitError)); return; end
        -- LOTRO imports must run on the UI thread, before the yielding search starts.
        local loaded, loadError = StatCapsBestGear.Load();
        if (not loaded) then status:SetText(T(loadError)); return; end
        local sets;
        sets, loadError = StatCapsSetDatabase.Calculate({}, context.level);
        if (not sets) then status:SetText(T(loadError)); return; end
        local names;
        names, loadError = StatCapsCompanion.Names();
        if (not names) then status:SetText(T(loadError)); return; end
        inputKey = StatCapsBestGear.InputKey(context, state);
        status:SetText(T("Searching supported gear and maximum-rank virtues..."));
        virtues:SetText(T("Theoretical active virtues: rank ") .. limit.rank .. " / " .. T("Unlocked slots: ") .. limit.slots);
        generate:SetEnabled(false); clear:SetEnabled(false); stop:SetEnabled(true);
        job = coroutine.create(function()
            return StatCapsBestGear.Run(CalcStat, context, state, options, function(stage, work)
                coroutine.yield(stage, work);
            end);
        end);
        win:SetWantsUpdates(true);
    end
    generate = button(win, "Generate best gear (Test)", 22, 219, 250, start);
    clear = button(win, "Clear exclusions / pins / levels", 286, 219, 288, function()
        options.excludedIds, options.excludedNames, options.itemLevels, options.pinned = {}, {}, {}, {};
        invalidate();
    end);
    stop = button(win, "Cancel search", 590, 219, 148, function()
        invalidate(); status:SetText(T("Search cancelled. No plan or virtue ranks changed."));
    end);
    stop:SetEnabled(false);
    button(win, "Set bonuses / effects", 22, 387, 235, function()
        if (not result) then status:SetText(T("Generate a preview first.")); return; end
        alternatives:ClearItems();
        local total = T("Supported proposed set totals:") .. "\n" .. valuesText(result.sets.values);
        alternatives:AddItem(label(nil, total, 0, 0, 420, textHeight(total, 49)));
        for _, row in ipairs(result.sets.rows) do
            local text = row.name .. " / " .. row.count .. "/" .. row.threshold .. " / "
                .. T(row.active and "Active" or "Inactive") .. "\n" .. valuesText(row.values);
            for _, warning in ipairs(row.warnings) do text = text .. "\n" .. T("Not compared: ") .. T(warning); end
            alternatives:AddItem(label(nil, text, 0, 0, 420, textHeight(text, 49) + 8));
        end
        if (#result.sets.rows == 0) then
            alternatives:AddItem(label(nil, "No proposed set bonuses.", 0, 0, 420, 50));
        end
    end);
    unverified.CheckedChanged = function() options.pinned = {}; invalidate(); end
    weapons.CheckedChanged = function() options.pinned = {}; invalidate(); end
    unsourced.CheckedChanged = function() options.pinned = {}; invalidate(); end
    confirmed.CheckedChanged = function() if (not confirmed:IsChecked()) then invalidate(); end end
    win.Update = function()
        for _ = 1, 4 do
            if (not job) then return; end
            local ok, value, detail = coroutine.resume(job);
            if (not ok) then
                cancel(); status:SetText(T("Experimental search failed: ") .. tostring(value)); return;
            end
            if (coroutine.status(job) == "dead") then
                cancel();
                if (not value) then status:SetText(T(detail)); return; end
                local fresh, state, err = getInputs();
                if (not fresh or not state or StatCapsBestGear.InputKey(fresh, state) ~= inputKey) then
                    confirmed:SetChecked(false);
                    status:SetText(T(err or "The snapshot or current bonuses changed during the search. Review and generate again."));
                    return;
                end
                result = value; win.lastResult = result;
                local choices = {};
                for _, virtue in ipairs(result.virtues) do choices[#choices + 1] = T(virtue.name) .. " " .. virtue.rank; end
                virtues:SetText(T("Max-rank virtues (not saved): ") .. table.concat(choices, ", ")
                    .. "\n" .. T("Gear + virtues vs snapshot: ") .. string.format("%+.2f", result.score));
                status:SetText(T("Preview ready. Heuristic search, not a proven global optimum. Eligible records: ") .. result.scanned
                    .. " / " .. T("Unsupported scaling: ") .. result.skipped .. " / " .. T("No known source: ") .. result.unsourced .. " / " .. T("Exclusions: ") .. exclusions()
                    .. " / " .. T("Unscored set effects: ") .. #result.sets.warnings);
                render(); return;
            end
            status:SetText(T(tostring(value)) .. " / " .. tostring(detail));
        end
    end
    win.VisibleChanged = function() if (not win:IsVisible()) then cancel(); end end
    win.CloseChildren = cancel;
    local context, _, err = getInputs();
    if (context) then
        header:SetText(context.characterName .. " / " .. T(context.className) .. " / " .. T("Level ") .. context.level
            .. " / " .. T(context.profile.name));
    else status:SetText(T(err or "The target snapshot is unavailable.")); end
    win:SetVisible(true); win:Activate();
    return win;
end
