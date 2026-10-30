StatCapsVirtueWindow = {};

local function T(text)
    return StatCapsLocalization.Text(text);
end

function StatCapsVirtueWindow.Open(getContext, savedSelection, saveSelection, tracking)
    local win = StatCapsTheme.Window();
    win:SetText(T("Stat Caps - Virtue planner"));
    win:SetSize(650, 650);
    StatCapsTheme.Panel(win, 650, 650);
    local width, height = Turbine.UI.Display.GetSize();
    win:SetPosition(math.max(0, (width - 650) / 2), math.max(0, (height - 650) / 2));
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
    local heading = label(win, "", 20, 38, 610, 45);
    heading:SetForeColor(Turbine.UI.Color(0.9, 0.8, 0.5));
    label(win, tracking and
        "Save all 21 earned ranks once using All virtue ranks. Rank-ups are tracked\nwhile loaded. Choose equipped virtues manually; None is valid." or
        "Enter your ACTUALLY equipped virtues/ranks. None is valid, even in all slots.\nRecommendations assume candidate max ranks, not ranks you have earned.", 20, 85, 610, 42);
    label(win, "Currently equipped", 20, 135, 380, 22);
    label(win, "Rank", 430, 135, 90, 22);
    local list = Turbine.UI.ListBox();
    list:SetParent(win);
    list:SetPosition(20, 365);
    list:SetSize(590, 205);
    local scroll = Turbine.UI.Lotro.ScrollBar();
    scroll:SetParent(win);
    scroll:SetPosition(614, 365);
    scroll:SetSize(12, 205);
    scroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    list:SetVerticalScrollBar(scroll);
    local function show(text)
        text = T(text or "");
        list:ClearItems();
        for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
            local line = "";
            for word in string.gmatch(paragraph, "%S+") do
                if (#line + #word > 66) then
                    list:AddItem(label(nil, line, 0, 0, 585, 22, true));
                    line = word;
                else
                    line = line == "" and word or line .. " " .. word;
                end
            end
            list:AddItem(label(nil, line, 0, 0, 585, 22, true));
        end
    end
    label(win, "Passives stay in live totals; they are NOT added again or projected for rank-ups.\nBase conversions only; power/regeneration are shown but not scored.\nSnapshot estimate: confirm the game tooltips and recalculate after changes.", 20, 580, 610, 60);
    local picker = StatCapsTheme.Window();
    picker:SetText(T("Stat Caps - Select equipped virtue"));
    picker:SetSize(340, 400);
    StatCapsTheme.Panel(picker, 340, 400);
    picker:SetPosition(math.max(0, (width - 340) / 2), math.max(0, (height - 400) / 2));
    local options = Turbine.UI.ListBox();
    options:SetParent(picker);
    options:SetPosition(15, 40);
    options:SetSize(290, 340);
    local optionScroll = Turbine.UI.Lotro.ScrollBar();
    optionScroll:SetParent(picker);
    optionScroll:SetPosition(310, 40);
    optionScroll:SetSize(12, 340);
    optionScroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    options:SetVerticalScrollBar(optionScroll);
    picker:SetVisible(false);
    local rankWindow, rankInputs, rankStatus;
    local rows, limits, confirm, refresh = {}, nil, nil, nil;
    local function invalidate()
        if (confirm) then confirm:SetChecked(false); end
        show("Choices changed. Confirm they match the game, then click Recommend virtues.");
    end
    for index = 1, 5 do
        local row = {};
        rows[index] = row;
        local stored = type(savedSelection) == "table" and savedSelection[index];
        row.name = type(stored) == "table" and stored.name or nil;
        row.button = StatCapsTheme.Button();
        row.button:SetParent(win);
        row.button:SetPosition(20, 160 + (index - 1) * 31);
        row.button:SetSize(395, 26);
        local function updateName()
            row.button:SetText(T("Slot " .. index .. ": " .. (row.name or "None")));
        end
        row.rank = Turbine.UI.Lotro.TextBox();
        row.rank:SetParent(win);
        row.rank:SetPosition(430, 160 + (index - 1) * 31);
        row.rank:SetSize(90, 26);
        row.rank:SetMultiline(false);
        row.rank:SetBackColor(Turbine.UI.Color(0.1, 0.12, 0.16));
        row.rank:SetForeColor(Turbine.UI.Color(1, 1, 1));
        row.rank:SetFont(Turbine.UI.Lotro.Font.Verdana14);
        row.rank:SetText(row.name and tostring(stored.rank or "") or "");
        row.rank.TextChanged = invalidate;
        row.button.Click = function()
            if (not limits) then show("Select a build and reopen the planner first."); return; end
            options:ClearItems();
            local names = { "None" };
            for _, virtue in ipairs(StatCapsVirtueData.virtues) do names[#names + 1] = virtue.name; end
            for _, name in ipairs(names) do
                local choice = name;
                local button = StatCapsTheme.Button();
                button:SetSize(280, 27);
                button:SetText(T(choice));
                button.Click = function()
                    row.name = choice ~= "None" and choice or nil;
                    local earned = tracking and tonumber(tracking.ranks[row.name]);
                    row.rank:SetText(row.name and tostring(earned and math.min(earned, limits.rank) or
                        (tracking and "" or limits.rank)) or "");
                    row.rank:SetEnabled(not tracking and row.name ~= nil);
                    updateName();
                    picker:SetVisible(false);
                    invalidate();
                end
                options:AddItem(button);
            end
            picker:SetVisible(true);
            picker:Activate();
        end
        updateName();
    end
    confirm = Turbine.UI.Lotro.CheckBox();
    confirm:SetParent(win);
    confirm:SetPosition(20, 320);
    confirm:SetSize(600, 22);
    confirm:SetText(T("These choices/ranks match my equipped virtues (including None)."));
    local function invalidateConfirmed()
        confirm:SetChecked(false);
        invalidate();
    end
    for _, row in ipairs(rows) do
        row.rank.TextChanged = not tracking and invalidateConfirmed or nil;
    end
    local recommend = StatCapsTheme.Button();
    recommend:SetParent(win);
    recommend:SetPosition(20, 340);
    recommend:SetSize(210, 24);
    recommend:SetText(T("Recommend virtues"));
    local none = StatCapsTheme.Button();
    none:SetParent(win);
    none:SetPosition(250, 340);
    none:SetSize(220, 24);
    none:SetText(T("No virtues equipped"));
    none.Click = function()
        for index, row in ipairs(rows) do
            row.name = nil;
            row.button:SetText(T("Slot " .. index .. ": None"));
            row.rank:SetText("");
            row.rank:SetEnabled(false);
        end
        invalidateConfirmed();
    end
    if (tracking) then
        local edit = StatCapsTheme.Button();
        edit:SetParent(win);
        edit:SetPosition(480, 340);
        edit:SetSize(145, 24);
        edit:SetText(T("All virtue ranks"));
        rankWindow = StatCapsTheme.Window();
        rankWindow:SetText(T("Stat Caps - All virtue ranks"));
        rankWindow:SetSize(440, 590);
        StatCapsTheme.Panel(rankWindow, 440, 590);
        rankWindow:SetPosition(math.max(0, (width - 440) / 2), math.max(0, (height - 590) / 2));
        label(rankWindow, "Enter all earned ranks once; 0 means untrained.\nBlank means unknown. Missed rank-ups need correction.", 20, 40, 400, 44);
        local rankList = Turbine.UI.ListBox();
        rankList:SetParent(rankWindow);
        rankList:SetPosition(20, 90);
        rankList:SetSize(380, 390);
        local rankScroll = Turbine.UI.Lotro.ScrollBar();
        rankScroll:SetParent(rankWindow);
        rankScroll:SetPosition(405, 90);
        rankScroll:SetSize(12, 390);
        rankScroll:SetOrientation(Turbine.UI.Orientation.Vertical);
        rankList:SetVerticalScrollBar(rankScroll);
        rankInputs = {};
        for _, virtue in ipairs(StatCapsVirtueData.virtues) do
            local row = Turbine.UI.Control();
            row:SetSize(375, 30);
            label(row, virtue.name, 0, 2, 240, 26);
            local input = Turbine.UI.Lotro.TextBox();
            input:SetParent(row);
            input:SetPosition(255, 0);
            input:SetSize(100, 26);
            input:SetMultiline(false);
            input:SetFont(Turbine.UI.Lotro.Font.Verdana14);
            input:SetBackColor(Turbine.UI.Color(0.1, 0.12, 0.16));
            input:SetForeColor(Turbine.UI.Color(1, 1, 1));
            rankInputs[virtue.name] = input;
            rankList:AddItem(row);
        end
        rankStatus = label(rankWindow, "", 20, 485, 400, 52);
        local save = StatCapsTheme.Button();
        save:SetParent(rankWindow);
        save:SetPosition(20, 545);
        save:SetSize(190, 26);
        save:SetText(T("Save all virtue ranks"));
        save.Click = function()
            local values = {};
            for name, input in pairs(rankInputs) do values[name] = input:GetText(); end
            local normalized, err = StatCapsVirtues.ValidateRanks(values);
            if (not normalized) then rankStatus:SetText(T(err)); return; end
            for name, rank in pairs(normalized) do tracking.ranks[name] = rank; end
            tracking.save();
            rankWindow:SetVisible(false);
            refresh();
            invalidateConfirmed();
        end
        edit.Click = function()
            for name, input in pairs(rankInputs) do
                local rank = tracking.ranks[name];
                input:SetText(rank ~= nil and tostring(rank) or "");
            end
            rankStatus:SetText(T("English rank-up messages are recognized when available.\nOther wording/languages may need manual correction."));
            rankWindow:SetVisible(true);
            rankWindow:Activate();
        end
        rankWindow:SetVisible(false);
    end
    refresh = function()
        local context, err = getContext();
        if (not context) then show(err); return; end
        limits, err = StatCapsVirtues.Limits(context.level);
        if (not limits) then show(err); return; end
        heading:SetText(T(context.profile.name .. " / " .. context.tierName .. " / Level " .. context.level ..
            "\n" .. limits.slots .. " slots unlocked; maximum virtue rank " .. limits.rank .. "."));
        for index, row in ipairs(rows) do
            row.button:SetEnabled(index <= limits.slots);
            if (tracking) then
                local rank = row.name and tonumber(tracking.ranks[row.name]);
                row.rank:SetText(rank and tostring(math.min(rank, limits.rank)) or "");
            end
            row.rank:SetEnabled(not tracking and index <= limits.slots and row.name ~= nil);
            row.button:SetText(T("Slot " .. index .. ": " .. (row.name or "None") ..
                (index > limits.slots and " (locked)" or "")));
        end
        return context;
    end
    recommend.Click = function()
        picker:SetVisible(false);
        local context = refresh();
        if (not context) then return; end
        if (not confirm:IsChecked()) then
            show("Confirm that the entered equipped virtues/ranks match your character first.");
            return;
        end
        local selection = {};
        for index, row in ipairs(rows) do
            if (row.name) then selection[index] = { name = row.name, rank = row.rank:GetText() }; end
        end
        local result, err = StatCapsVirtues.Recommend(CalcStat, context.className,
            context.profile, context.snapshot, context.level, selection, tracking and tracking.ranks);
        if (not result) then show(err); return; end
        saveSelection(result.selection);
        local lines = {
            result.actualRanks and "Using your saved earned ranks, limited by character level." or
                "Assuming ALL candidate virtues at rank " .. result.limits.rank .. ".",
            "Best scored full set: " .. StatCapsScoring.FormatScore(result.score) ..
                " display points (score x 1,000) vs entered current set.",
            "Only below-cap portions count; passive bonuses remain unchanged.", ""
        };
        if (context.profile.scoring) then
            lines[#lines + 1] = StatCapsScoring.Description(context.profile);
        end
        if (result.limits.slots == 0) then lines[#lines + 1] = "No virtue slots unlocked yet."; end
        if (result.actualRanks and #result.choices < result.limits.slots) then
            lines[#lines + 1] = "Untrained virtues are excluded; remaining slots stay empty.";
        end
        local labels = { Power = "Power (unscored)", ICMR = "In-combat morale regen (unscored)" };
        for _, field in ipairs(StatCapsManual.Fields) do labels[field[1]] = field[2]; end
        for index, virtue in ipairs(result.choices) do
            lines[#lines + 1] = index .. ". " .. virtue.name .. " - rank " .. virtue.rank;
            local stats = {};
            for key, value in pairs(virtue.values) do
                if (value ~= 0) then stats[#stats + 1] = (labels[key] or key) .. " +" .. value; end
            end
            table.sort(stats);
            lines[#lines + 1] = table.concat(stats, ", ");
        end
        lines[#lines + 1] = "";
        lines[#lines + 1] = "Largest net scored changes:";
        for rank, detail in ipairs(result.details) do
            if (rank <= 4) then
                lines[#lines + 1] = detail.label .. string.format(": %+.1f / ", detail.delta) ..
                    StatCapsScoring.FormatScore(detail.points) .. " display points";
            end
        end
        show(table.concat(lines, "\n"));
    end
    win.VisibleChanged = function()
        picker:SetVisible(false);
        if (rankWindow) then rankWindow:SetVisible(false); end
        if (win:IsVisible()) then
            confirm:SetChecked(false);
            refresh();
            show("Confirm your current equipped virtues/ranks, then click Recommend virtues.");
        end
    end
    win.RanksChanged = function(name, rank)
        if (rankWindow and rankWindow:IsVisible()) then
            rankInputs[name]:SetText(tostring(rank));
            rankStatus:SetText(T(name .. " updated to rank " .. rank .. " from gameplay.\nOther unsaved entries have been kept."));
        end
        invalidateConfirmed();
        refresh();
    end
    win.HideChildren = function()
        picker:SetVisible(false);
        if (rankWindow) then rankWindow:SetVisible(false); end
    end
    refresh();
    win:SetVisible(true);
    win:Activate();
    return win;
end
