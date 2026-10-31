import "Turbine";
import "Turbine.Gameplay";
import "Turbine.UI";
import "Turbine.UI.Lotro";
import "StatCaps.Localization";
import "StatCaps.Theme";
import "StatCaps.ThemeProfiles";
import "StatCaps.MainSkin";
import "StatCaps.Caps";
import "StatCaps.Recommendations";
import "StatCaps.Scoring";
import "StatCaps.Comparison";
import "StatCaps.CharacterProfiles";
import "StatCaps.Companion";
import "StatCaps.ManualItems";
import "StatCaps.ItemDatabase";
import "StatCaps.ItemLinks";
import "StatCaps.SetDatabase";
import "StatCaps.Loadouts";
import "StatCaps.LoadoutWindow";
import "StatCaps.VirtueData";
import "StatCaps.Virtues";
import "StatCaps.VirtueWindow";

local function T(text)
    return StatCapsLocalization.Text(text);
end

local hasCalcStat, calcStatError = pcall(import, "Giseldah.CalcStat.CalcStatFull");
hasCalcStat = hasCalcStat and type(CalcStat) == "function";
if (not hasCalcStat) then
    Turbine.Shell.WriteLine("StatCaps: full CalcStat library required: " .. tostring(calcStatError));
end

local SETTINGS_KEY = "StatCaps";
local PROFILE_KEY = "StatCapsCharacterProfiles";
local LOADOUT_KEY = "StatCapsLoadoutPlans";
local LEVEL_CAP = 160; -- highest level CalcStat has data for
local REFRESH_SECONDS = 1;

local WIN_W = 550;
local PAD_X, PAD_TOP = 15, 168;
local ROW_H, SECTION_H = 26, 28;
local COL = {
    { x = 15, w = 170 },  -- name
    { x = 185, w = 85 },  -- rating
    { x = 270, w = 85 },  -- limit
    { x = 355, w = 95 },  -- difference
    { x = 450, w = 85 },  -- effective % / cap %
};
local BAR_W = WIN_W - 2 * PAD_X;

local ARMOUR_NAMES = { [1] = "Light", [2] = "Medium", [3] = "Heavy" };
local FONT = Turbine.UI.Lotro.Font.Verdana14;
local FONT_SMALL = Turbine.UI.Lotro.Font.Verdana12;

-- stat: CalcStat name prefix ("Mit" picks Light/Medium/Heavy by class armour type)
local ROWS = {
    { section = "Offence" },
    { key = "PhysicalMastery", label = "Physical Mastery", stat = "OutDmg", get = function(a)
        return math.max(a:GetMeleeDamage() or 0, a:GetRangeDamage() or 0);
    end },
    { key = "TacticalMastery", label = "Tactical Mastery", stat = "OutDmg", get = function(a) return a:GetTacticalDamage(); end },
    { label = "Critical Rating", stat = "CritHit", get = function(a) return a:GetBaseCriticalHitChance(); end },
    { label = "Finesse", stat = "Finesse", get = function(a) return a:GetFinesse(); end },
    { label = "Outgoing Healing", stat = "OutHeal", hideZero = true, get = function(a) return a:GetOutgoingHealing(); end },
    { section = "Defence" },
    { key = "PhysicalMitigation", label = "Physical Mitigation", stat = "Mit", get = function(a) return a:GetCommonMitigation(); end },
    { key = "SpecialMitigation", label = "Orc/Fell-craft Mit.", stat = "Mit", get = function(a) return a:GetPhysicalMitigation(); end },
    { key = "TacticalMitigation", label = "Tactical Mitigation", stat = "Mit", get = function(a) return a:GetTacticalMitigation(); end },
    { label = "Critical Defence", stat = "CritDef", get = function(a) return a:GetBaseCriticalHitAvoidance(); end },
    { label = "Resistance", stat = "Resist", get = function(a) return a:GetBaseResistance(); end },
    { key = "Block", label = "Block", stat = "BPE", can = "CanBlock", get = function(a) return a:GetBlock(); end },
    { key = "Parry", label = "Parry", stat = "BPE", can = "CanParry", get = function(a) return a:GetParry(); end },
    { key = "Evade", label = "Evade", stat = "BPE", can = "CanEvade", get = function(a) return a:GetEvade(); end },
    { label = "Incoming Healing", stat = "InHeal", get = function(a) return a:GetIncomingHealing(); end },
};

local function Fmt(n)
    local s = tostring(math.floor(math.abs(n) + 0.5));
    local replaced;
    repeat
        s, replaced = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2");
    until replaced == 0;
    return (n < 0 and "-" or "") .. s;
end

local function FmtSigned(n)
    if (math.abs(n) < 0.5) then
        return "0";
    end
    return (n > 0 and "+" or "") .. Fmt(n);
end

local function ColorFor(ratio)
    if (ratio > 1.05) then
        return Turbine.UI.Color(1, 0.55, 0.15); -- well above the limit: surplus is wasted
    elseif (ratio >= 0.995) then
        return Turbine.UI.Color(0.25, 0.95, 0.3); -- at the limit
    elseif (ratio >= 0.9) then
        return Turbine.UI.Color(0.65, 0.95, 0.25);
    elseif (ratio >= 0.7) then
        return Turbine.UI.Color(1, 0.85, 0.2);
    end
    return Turbine.UI.Color(1, 0.3, 0.3);
end

local settings = {};
do
    local ok, loaded = pcall(Turbine.PluginData.Load, Turbine.DataScope.Character, SETTINGS_KEY);
    if (ok and type(loaded) == "table") then
        settings = loaded;
    end
end

local characterProfiles = {};
do
    local ok, loaded = pcall(Turbine.PluginData.Load, Turbine.DataScope.Account, PROFILE_KEY);
    if (ok and type(loaded) == "table") then
        characterProfiles = StatCapsCharacterProfiles.Normalize(loaded);
    elseif (not ok) then
        Turbine.Shell.WriteLine("StatCaps: could not load saved character profiles: " .. tostring(loaded));
    end
end

local loadoutPlans = {};
local loadoutLoadError;
do
    local ok, loaded = pcall(Turbine.PluginData.Load, Turbine.DataScope.Account, LOADOUT_KEY);
    if (ok and type(loaded) == "table") then
        loadoutPlans = loaded;
    elseif (not ok) then
        loadoutLoadError = tostring(loaded);
        Turbine.Shell.WriteLine("StatCaps: could not load saved loadout plans: " .. tostring(loaded));
    elseif (loaded ~= nil) then
        loadoutLoadError = "Saved loadout data is invalid.";
        Turbine.Shell.WriteLine("StatCaps: could not load saved loadout plans: " .. loadoutLoadError);
    end
end

if (type(settings.virtueRanks) ~= "table") then
    settings.virtueRanks = {};
    for _, choice in pairs(type(settings.virtues) == "table" and settings.virtues or {}) do
        if (type(choice) == "table" and StatCapsVirtues.Find(choice.name)) then
            settings.virtueRanks[choice.name] = tonumber(choice.rank);
        end
    end
end

local tierNames = { "Landscape", "T1", "T2", "T3" };
local selectedTier = tonumber(settings.tier) or 1;
if (not tierNames[selectedTier]) then
    selectedTier = 1;
end
local SaveSettings;

local player = Turbine.Gameplay.LocalPlayer.GetInstance();
local playerName;
do
    local ok, name = pcall(function() return player:GetName(); end);
    if (ok and type(name) == "string" and name ~= "") then playerName = name; end
end
local lastProfileSave = -60;
local equipmentSaveError;
local attributes;
local attributeReadErrors = {};
local selectedBuild = settings.build;

settings.appearance = nil;
if (type(settings.theme) == "table") then settings.theme.mode = nil; end
StatCapsTheme.Configure(StatCapsThemeProfiles.Resolve(settings.theme,
    Turbine.Gameplay.LocalPlayer.GetInstance(), Turbine.Gameplay, hasCalcStat and CalcStat or nil));
if (StatCapsTheme.profile.warning) then
    Turbine.Shell.WriteLine("StatCaps: " .. T(StatCapsTheme.profile.warning));
end
local win, resizeMainPanel = StatCapsMainSkin.Window(function() SaveSettings(); end);
local dispW, dispH = Turbine.UI.Display.GetSize();
local posX = tonumber(settings.x) or math.floor(dispW * 0.7);
local posY = tonumber(settings.y) or math.floor(dispH * 0.2);
win:SetPosition(math.max(0, math.min(posX, dispW - 100)), math.max(0, math.min(posY, dispH - 100)));

local adviceWin = StatCapsTheme.Window();
adviceWin:SetText(T("Stat Caps - Build advice"));
adviceWin:SetSize(450, 570);
StatCapsTheme.Panel(adviceWin, 450, 570);
adviceWin:SetPosition(math.max(0, math.min(posX + WIN_W, dispW - 450)),
    math.max(0, math.min(posY, dispH - 570)));
adviceWin:SetVisible(false);
local adviceList = Turbine.UI.ListBox();
adviceList:SetParent(adviceWin);
adviceList:SetPosition(15, 166);
adviceList:SetSize(405, 388);
adviceList:SetBackColor(Turbine.UI.Color(0.055, 0.06, 0.07));
local adviceScroll = Turbine.UI.Lotro.ScrollBar();
adviceScroll:SetParent(adviceWin);
adviceScroll:SetPosition(423, 166);
adviceScroll:SetSize(12, 388);
adviceScroll:SetOrientation(Turbine.UI.Orientation.Vertical);
adviceList:SetVerticalScrollBar(adviceScroll);
local lastAdviceText;
local function SetAdviceText(text)
    text = T(text or "");
    if (lastAdviceText == text) then return; end
    lastAdviceText = text;
    local lines = {};
    for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
        local line = "";
        for word in string.gmatch(paragraph, "%S+") do
            if (#line + #word + 1 > 48 and line ~= "") then
                lines[#lines + 1] = line;
                line = word;
            else
                line = line == "" and word or line .. " " .. word;
            end
        end
        lines[#lines + 1] = line;
    end
    adviceList:ClearItems();
    for _, line in ipairs(lines) do
        local label = Turbine.UI.Label();
        label:SetSize(400, 20);
        label:SetFont(FONT);
        label:SetForeColor(Turbine.UI.Color(0.92, 0.9, 0.84));
        if (line:match(":$")) then
            label:SetForeColor(Turbine.UI.Color(0.9, 0.8, 0.5));
        end
        label:SetTextAlignment(Turbine.UI.ContentAlignment.TopLeft);
        label:SetMouseVisible(false);
        label:SetText(line);
        adviceList:AddItem(label);
    end
end
local adviceHeading = Turbine.UI.Label();
adviceHeading:SetParent(adviceWin);
adviceHeading:SetPosition(15, 37);
adviceHeading:SetSize(310, 22);
adviceHeading:SetFont(FONT);
adviceHeading:SetForeColor(Turbine.UI.Color(0.9, 0.8, 0.5));
local adviceTab = "Priorities";
local adviceTabs = {};
local skippedGoals = {};
local goalContext;
local currentGoal;
local currentSnapshot;
local nextButton = StatCapsTheme.Button();
nextButton:SetParent(adviceWin);
nextButton:SetPosition(15, 136);
nextButton:SetSize(205, 24);
nextButton:SetText(T("What next?"));
nextButton:SetEnabled(false);
local resetButton = StatCapsTheme.Button();
resetButton:SetParent(adviceWin);
resetButton:SetPosition(225, 136);
resetButton:SetSize(205, 24);
resetButton:SetText(T("Reset skipped"));
resetButton:SetEnabled(false);
local buildButton = StatCapsMainSkin.Button(win, "Build advice - choose a build", PAD_X, 124, "action");
buildButton.Click = function() adviceWin:SetVisible(not adviceWin:IsVisible()); end;
local buildButtons = {};
local Refresh;
local manualWin;
local virtueWin;
local scoringWin;
local function BuildProfile(className)
    local profile = StatCapsAdvice.Profile(className, selectedBuild);
    local key = selectedBuild and StatCapsScoring.Key(className, selectedBuild);
    return StatCapsScoring.Resolve(profile, type(settings.scoring) == "table" and settings.scoring[key] or nil, CalcStat);
end
local manualButton = StatCapsMainSkin.Button(win, "Compare items", PAD_X + 265, 124, "action");
local function PlanningContext()
    if (not hasCalcStat) then return nil, "The full CalcStat library is required."; end
    Refresh();
    local className = CalcStat("ClassName", player:GetClass());
    local profile = BuildProfile(className);
    if (not profile) then return nil, "Select your build in Build advice first."; end
    if (not currentSnapshot or currentSnapshot.level ~= player:GetLevel()) then
        return nil, "Current character stats are unavailable or this level is unsupported.";
    end
    return { className = className, profile = profile, snapshot = currentSnapshot,
        tierName = tierNames[selectedTier], level = currentSnapshot.level,
        equippedVirtues = settings.virtues, earnedVirtueRanks = settings.virtueRanks };
end

local function SaveAccountProfiles()
    local ok, err = pcall(Turbine.PluginData.Save, Turbine.DataScope.Account,
        PROFILE_KEY, characterProfiles);
    if (not ok) then
        Turbine.Shell.WriteLine("StatCaps: could not save character profiles: " .. tostring(err));
        return nil, tostring(err);
    end
    return true;
end

local function SaveCharacterProfile(className, force)
    if (not playerName or not currentSnapshot) then return; end
    local now = Turbine.Engine.GetGameTime();
    if (not force and now - lastProfileSave < 60) then return; end
    local existing = StatCapsCharacterProfiles.Get(characterProfiles, playerName);
    local equipped, equipmentError = StatCapsItemDatabase.Equipped(player);
    local items = existing and existing.items or {};
    if (equipped) then
        items = StatCapsCharacterProfiles.CaptureEquipment(items, equipped, currentSnapshot.level);
        equipmentSaveError = nil;
    elseif (equipmentSaveError ~= equipmentError) then
        equipmentSaveError = equipmentError;
        Turbine.Shell.WriteLine("StatCaps: equipment snapshot was not refreshed: " .. tostring(equipmentError));
    end
    local scoringKey = selectedBuild and StatCapsScoring.Key(className, selectedBuild);
    local profile, err = StatCapsCharacterProfiles.Put(characterProfiles, playerName, {
        name = playerName, className = className, level = currentSnapshot.level,
        build = selectedBuild, tier = selectedTier,
        scoring = scoringKey and type(settings.scoring) == "table" and settings.scoring[scoringKey] or nil,
        snapshot = currentSnapshot, items = items,
        virtues = settings.virtues, virtueRanks = settings.virtueRanks,
        equipmentCaptured = equipped ~= nil or (existing and existing.equipmentCaptured)
    });
    if (not profile) then
        Turbine.Shell.WriteLine("StatCaps: could not update saved character profile: " .. tostring(err));
        return;
    end
    local ok = SaveAccountProfiles();
    if (ok) then lastProfileSave = now; end
end

local function ComparisonContext(profileKey)
    if (not profileKey or profileKey == playerName) then return PlanningContext(); end
    local saved = StatCapsCharacterProfiles.Get(characterProfiles, profileKey);
    if (not saved) then
        return nil, "Saved character profile is unavailable. Log in to that character to refresh it.";
    end
    local profile = StatCapsAdvice.Profile(saved.className, saved.build);
    if (not profile) then
        return nil, "The saved character has no supported build. Select its build and log in again to save it.";
    end
    StatCapsScoring.Resolve(profile, saved.scoring, CalcStat);
    return {
        className = saved.className, profile = profile, snapshot = saved.snapshot,
        tierName = tierNames[saved.tier] or "Landscape", level = saved.level,
        equippedVirtues = saved.virtues, earnedVirtueRanks = saved.virtueRanks, savedCharacter = saved,
        savedCharacterKey = profileKey
    };
end

local function SaveCharacterItem(equipmentSlot, name, values, category, characterLevel, equipmentKey)
    if (not playerName) then
        return nil, "LOTRO did not provide this character's name; the baseline cannot be saved.";
    end
    local item, err = StatCapsCharacterProfiles.PutItem(characterProfiles, playerName,
        equipmentSlot, name, values, category, characterLevel, equipmentKey);
    if (not item) then return nil, err; end
    return SaveAccountProfiles();
end

local function SavedProfiles()
    local list = {};
    for _, entry in ipairs(StatCapsCharacterProfiles.List(characterProfiles)) do
        if (entry.key ~= playerName) then
            list[#list + 1] = {
                key = entry.key, name = entry.profile.name,
                className = entry.profile.className, level = entry.profile.level,
                build = entry.profile.build, items = entry.profile.items
            };
        end
    end
    return list;
end

local loadoutWin;
local function LoadoutContext(profileKey)
    local context, err = ComparisonContext(profileKey);
    if (not context) then return nil, err; end
    if (context.savedCharacter) then
        if (not context.savedCharacter.equipmentCaptured) then
            return nil, "Equipment snapshot is unavailable. Load StatCaps on that character once.";
        end
        context.equipment = context.savedCharacter.items;
        context.characterName = context.savedCharacter.name;
    else
        local equipped;
        equipped, err = StatCapsItemDatabase.Equipped(player);
        if (not equipped) then return nil, err; end
        local saved = playerName and StatCapsCharacterProfiles.Get(characterProfiles, playerName);
        context.equipment = StatCapsCharacterProfiles.CaptureEquipment(saved and saved.items or {}, equipped, context.level);
        context.characterName = playerName;
    end
    return context;
end

local function OpenLoadouts(profileKey, selectCurrent)
    if (loadoutWin) then
        if (profileKey or selectCurrent) then loadoutWin.SelectTarget(profileKey); end
        loadoutWin:SetVisible(true);
        loadoutWin:Activate();
        return;
    end
    loadoutWin = StatCapsLoadoutWindow.Open(LoadoutContext, SavedProfiles,
        function(key) return loadoutPlans[key]; end,
        function(key, plan)
            if (loadoutLoadError) then
                return nil, "Saved loadout plans could not be loaded. Reload StatCaps before saving.";
            end
            local previous = loadoutPlans[key];
            loadoutPlans[key] = plan;
            local ok, err = pcall(Turbine.PluginData.Save, Turbine.DataScope.Account, LOADOUT_KEY, loadoutPlans);
            if (not ok) then
                loadoutPlans[key] = previous;
                Turbine.Shell.WriteLine("StatCaps: could not save loadout plan: " .. tostring(err));
                return nil, "Could not save loadout plan: " .. tostring(err);
            end
            return true;
        end, profileKey);
end

manualButton.Click = function()
    if (manualWin) then
        manualWin:SetVisible(true);
        manualWin:Activate();
        return;
    end
    manualWin = StatCapsManual.Open(ComparisonContext, SavedProfiles, SaveCharacterItem,
        function(key) OpenLoadouts(key, true); end);
end
nextButton.Click = function()
    if (currentGoal) then
        skippedGoals[currentGoal.key] = true;
        Refresh();
    end
end
resetButton.Click = function()
    skippedGoals = {};
    Refresh();
end
local adviceClass;
local function UpdateAdvice(className, samples, attributeValues)
    local context = tostring(className) .. ":" .. tostring(selectedBuild) .. ":" .. selectedTier;
    if (context ~= goalContext) then
        skippedGoals = {};
        goalContext = context;
    end
    currentGoal = nil;
    nextButton:SetEnabled(false);
    resetButton:SetEnabled(next(skippedGoals) ~= nil);
    adviceHeading:SetText(T((className or "Unknown class") .. " - choose your build"));
    local roles = StatCapsAdvice.Roles(className);
    if (adviceClass ~= className) then
        for _, button in ipairs(buildButtons) do button:SetVisible(false); end
        buildButtons = {};
        adviceClass = className;
        for index, role in ipairs(roles) do
            local choice = role;
            local button = StatCapsTheme.Button();
            button:SetParent(adviceWin);
            button:SetPosition(15 + (index - 1) * 105, 65);
            button:SetSize(100, 24);
            button:SetText(T(role));
            button.Click = function()
                selectedBuild = choice;
                Refresh();
                SaveSettings();
            end
            buildButtons[index] = button;
        end
    end
    local profile = BuildProfile(className);
    for index, button in ipairs(buildButtons) do
        button:SetEnabled(roles[index] ~= selectedBuild);
        button:SetText(T((roles[index] == selectedBuild and "> " or "") .. roles[index]));
    end
    if (#roles == 0) then
        buildButton:SetText(T("Build advice - unsupported class"));
        SetAdviceText("No recommendations are available for this class. Stat caps remain visible.");
        return;
    elseif (not profile) then
        buildButton:SetText(T("Build advice - choose a build"));
        SetAdviceText("Choose your role above for " .. className .. ".\n\n"
            .. "Select it manually when you change builds; StatCaps does not detect your trait specialization.\n\n"
            .. "Advice uses your current ratings and selected tier. Caps are reference limits, not mandatory gearing targets.");
        return;
    end
    buildButton:SetText(T("Build advice: " .. profile.name));
    local adjustedSamples, targetError = StatCapsScoring.AdviceSamples(profile, samples, player:GetLevel());
    if (not adjustedSamples) then SetAdviceText(targetError); return; end
    samples = adjustedSamples;
    local result = StatCapsAdvice.Evaluate(profile, samples);
    local progression = StatCapsAdvice.Next(profile, samples, skippedGoals);
    currentGoal = progression.goal;
    nextButton:SetEnabled(currentGoal ~= nil and adviceTab == "Priorities");
    local mainAttributes = StatCapsAdvice.Attributes(CalcStat, className, attributeValues);
    if (adviceTab == "Attributes") then
        local lines = { profile.name .. " / " .. tierNames[selectedTier],
            "Main attributes have no hard caps. Base gains per point below are class-specific, before trait/buff multipliers.", "",
            StatCapsAdvice.AttributeHint(result, mainAttributes) };
        if (profile.role == "Tank") then
            lines[#lines + 1] = "Tank: balance Vitality/morale with mitigations; there is no universal Vitality target.";
        end
        for _, item in ipairs(mainAttributes) do
            lines[#lines + 1] = "";
            lines[#lines + 1] = item.name .. ": " .. (item.value and Fmt(item.value) or "unavailable");
            lines[#lines + 1] = #item.text > 0 and table.concat(item.text, ", ")
                or "No conversion data available.";
        end
        lines[#lines + 1] = "";
        lines[#lines + 1] = "Source: installed CalcStat full library. Bonuses already contribute to your ratings; do not add them again. Check in-game tooltips after game updates.";
        SetAdviceText(table.concat(lines, "\n"));
        return;
    end
    local lines = { profile.name .. " / " .. tierNames[selectedTier], "" };
    if (profile.scoringError) then
        SetAdviceText(profile.scoringError .. "\nOpen Scoring to correct the settings.");
        return;
    end
    if (currentGoal) then
        lines[#lines + 1] = (currentGoal.situational and "Consider next: " or "Next priority: ") .. currentGoal.label;
        lines[#lines + 1] = Fmt(currentGoal.amount) .. (currentGoal.key == "Finesse"
            and profile.scoring and profile.scoring.finesseTarget ~= nil
            and " below your chosen Finesse target." or " below the selected tier's cap.");
        lines[#lines + 1] = currentGoal.reason or (currentGoal.situational
            and "Optional encounter-dependent improvement, not a requirement to max this stat."
            or "A useful build priority; balance it with the fight's needs rather than blindly maxing it.");
        lines[#lines + 1] = StatCapsAdvice.AttributeHint({ gaps = { currentGoal } }, mainAttributes);
    else
        lines[#lines + 1] = "No further uncapped rating priorities in this build's list.";
        lines[#lines + 1] = "Review morale/Vitality, gear bonuses and encounter needs; there is no universal next stat to max.";
    end
    if (progression.unavailable > 0) then
        lines[#lines + 1] = "Some ratings are unavailable; recommendations may be incomplete.";
    end
    lines[#lines + 1] = "Reached caps are skipped automatically. What next? skips only for planning; it does not mark a stat as capped.";
    lines[#lines + 1] = "Skipped choices reset when build or tier changes. Reset skipped starts over.";
    lines[#lines + 1] = "";
    lines[#lines + 1] = profile.note;
    lines[#lines + 1] = "";
    if (profile.scoring) then
        lines[#lines + 1] = profile.scoring.mode == "essence"
            and "Active EV stat weights (% of reference essence value):"
            or "Active cap-normalized weights (points per 1% of cap):";
        local effectiveWeights = StatCapsAdvice.Weights(profile);
        for _, field in ipairs(StatCapsScoring.Fields) do
            local classWeight = profile.scoring.weights[field[1]];
            local roleWeight = profile.scoring.roleWeights[field[1]];
            local weight = effectiveWeights[field[1]];
            if (weight and weight > 0) then
                local value = weight and (profile.scoring.mode == "essence"
                    and string.format("%.2f", weight) or tostring(weight)) or "inactive";
                lines[#lines + 1] = field[2] .. ": " .. value .. " (" ..
                    "(" .. tostring(classWeight or 0) .. " x 5 + " ..
                    tostring(roleWeight or 0) .. "/5) / 6"
                    .. (not weight and " (no target or derived value)" or "");
            end
        end
        lines[#lines + 1] = "";
    end
    lines[#lines + 1] = "Relevant cap headroom (not required targets):";
    for _, item in ipairs(result.gaps) do
        lines[#lines + 1] = item.label .. ": " .. Fmt(item.amount) .. " below cap.";
    end
    if (#result.gaps == 0) then
        lines[#lines + 1] = #result.unavailable == 0
            and "Your primary ratings are at or above these caps."
            or "Some ratings are unavailable; cannot assess all priorities.";
    end
    if (#result.surplus > 0) then
        local item = result.surplus[1];
        lines[#lines + 1] = item.label .. ": " .. Fmt(item.amount) ..
            " above this target; consider shifting rating if no extra debuffs apply.";
    end
    if (#result.unavailable > 0 and #result.gaps > 0) then
        lines[#lines + 1] = "Some priority ratings are unavailable.";
    end
    lines[#lines + 1] = "";
    lines[#lines + 1] = StatCapsAdvice.AttributeHint(result, mainAttributes);
    lines[#lines + 1] = "";
    lines[#lines + 1] = profile.ignore;
    lines[#lines + 1] = profile.situational;
    lines[#lines + 1] = "Finesse depends on enemy B/P/E or resists and your actual skills, including tank threat skills. Set an encounter target in Scoring; the hard cap is not a gearing goal.";
    lines[#lines + 1] = "General guidance only. Morale, buffs, traits and encounter mechanics also matter.";
    SetAdviceText(table.concat(lines, "\n"));
end

local scoringButton = StatCapsTheme.Button();
scoringButton:SetParent(adviceWin);
scoringButton:SetPosition(330, 37);
scoringButton:SetSize(100, 24);
scoringButton:SetText(T("Scoring"));
scoringButton.Click = function()
    local context, err = PlanningContext();
    if (not context) then SetAdviceText(err); return; end
    if (scoringWin) then scoringWin:SetVisible(false); end
    local className, role = context.className, selectedBuild;
    local key = StatCapsScoring.Key(className, role);
    local config = type(settings.scoring) == "table" and settings.scoring[key];
    scoringWin = StatCapsScoring.Open(StatCapsAdvice.Profile(className, role), config, function(value)
        if (type(settings.scoring) ~= "table") then settings.scoring = {}; end
        settings.scoring[key] = value;
        skippedGoals = {};
        SaveSettings();
        Refresh();
        if (manualWin) then manualWin:SetVisible(false); end
        if (virtueWin) then virtueWin.HideChildren(); virtueWin:SetVisible(false); end
    end, CalcStat);
end

for index, name in ipairs({ "Priorities", "Attributes" }) do
    local choice = name;
    local button = StatCapsTheme.Button();
    button:SetParent(adviceWin);
    button:SetPosition(15 + (index - 1) * 105, 100);
    button:SetSize(100, 24);
    button:SetText(T(name));
    button:SetEnabled(name ~= adviceTab);
    button.Click = function()
        adviceTab = choice;
        for tabName, tab in pairs(adviceTabs) do tab:SetEnabled(tabName ~= adviceTab); end
        Refresh();
    end
    adviceTabs[name] = button;
end
do
    local virtueButton = StatCapsTheme.Button();
    virtueButton:SetParent(adviceWin);
    virtueButton:SetPosition(330, 100);
    virtueButton:SetSize(100, 24);
    virtueButton:SetText(T("Virtues"));
    virtueButton.Click = function()
        if (virtueWin) then
            virtueWin:SetVisible(true);
            virtueWin:Activate();
            return;
        end
        virtueWin = StatCapsVirtueWindow.Open(PlanningContext, settings.virtues, function(selection)
            settings.virtues = selection;
            SaveSettings();
        end, { ranks = settings.virtueRanks, save = function() SaveSettings(); end });
    end
end

local function MakeLabel(text, col, font, align)
    local label = Turbine.UI.Label();
    label:SetParent(win);
    label:SetFont(font or FONT);
    label:SetForeColor(Turbine.UI.Color(0.92, 0.9, 0.84));
    label:SetTextAlignment(align or Turbine.UI.ContentAlignment.MiddleRight);
    label:SetMouseVisible(false);
    label:SetSize(col.w, ROW_H - 5);
    label:SetPosition(col.x, 0);
    label:SetText(T(text or ""));
    return label;
end

local header = MakeLabel("", { x = PAD_X, w = BAR_W }, FONT, Turbine.UI.ContentAlignment.MiddleLeft);
header:SetPosition(83, 42);
header:SetWidth(280);
header:SetFont(FONT_SMALL);
header:SetForeColor(Turbine.UI.Color(0.9, 0.8, 0.5));

local columnTitles = {};
for i, title in ipairs({ "", "Rating", "Limit", "Over / Under", "Effective %" }) do
    columnTitles[i] = MakeLabel(title, COL[i], FONT_SMALL);
    columnTitles[i]:SetForeColor(Turbine.UI.Color(0.82, 0.79, 0.71));
end

local rowWidgets = {};
for index, def in ipairs(ROWS) do
    local w = {};
    if (def.section) then
        w.title = MakeLabel(def.section, { x = PAD_X, w = BAR_W }, FONT, Turbine.UI.ContentAlignment.MiddleLeft);
        w.title:SetForeColor(Turbine.UI.Color(0.9, 0.8, 0.5));
        w.title:SetHeight(SECTION_H);
        w.title:SetBackground(StatCapsTheme.Asset("main_section"));
    else
        w.background = Turbine.UI.Control();
        w.background:SetParent(win);
        w.background:SetSize(BAR_W, ROW_H);
        w.background:SetBackColor(index % 2 == 0
            and Turbine.UI.Color(0.075, 0.08, 0.09) or Turbine.UI.Color(0.11, 0.115, 0.125));
        w.background:SetMouseVisible(false);
        w.name = MakeLabel(def.label, COL[1], FONT, Turbine.UI.ContentAlignment.MiddleLeft);
        w.rating = MakeLabel("", COL[2]);
        w.limit = MakeLabel("", COL[3]);
        w.limit:SetForeColor(Turbine.UI.Color(0.8, 0.78, 0.72));
        w.diff = MakeLabel("", COL[4]);
        w.pct = MakeLabel("", COL[5], FONT_SMALL);
        w.track = Turbine.UI.Control();
        w.track:SetParent(win);
        w.track:SetBackColor(Turbine.UI.Color(0.18, 0.18, 0.18));
        w.track:SetMouseVisible(false);
        w.track:SetSize(BAR_W, 3);
        w.bar = Turbine.UI.Control();
        w.bar:SetParent(win);
        w.bar:SetMouseVisible(false);
        w.bar:SetSize(0, 3);
    end
    rowWidgets[index] = w;
end

local footer = MakeLabel("", { x = PAD_X, w = BAR_W }, FONT_SMALL, Turbine.UI.ContentAlignment.TopLeft);
footer:SetForeColor(Turbine.UI.Color(0.8, 0.78, 0.72));

local function SetRowVisible(w, visible)
    for _, control in pairs(w) do
        control:SetVisible(visible);
    end
end

local function SafeCalc(name, level, param)
    local ok, value = pcall(CalcStat, name, level, param);
    if (ok and type(value) == "number") then
        return value;
    end
    return nil;
end

Refresh = function()
    if (not hasCalcStat) then
        header:SetText(T("Requires the CalcStat library (Giseldah)."));
        header:SetSize(405, 40);
        for _, w in ipairs(rowWidgets) do
            SetRowVisible(w, false);
        end
        for _, t in ipairs(columnTitles) do
            t:SetVisible(false);
        end
        footer:SetVisible(false);
        SetAdviceText("Install Giseldah's full CalcStat library to calculate recommendations.");
        resizeMainPanel(WIN_W, 180);
        return;
    end

    attributes = player:GetAttributes();
    if (attributes == nil) then
        return;
    end

    local level = player:GetLevel();
    if (not level or level < 1 or level > LEVEL_CAP) then
        error("CalcStat data supports levels 1-160 only; cannot calculate this character's caps.");
    end
    local classId = player:GetClass();
    local nameOk, classNameStr = pcall(CalcStat, "ClassName", classId);
    if (not nameOk or type(classNameStr) ~= "string" or classNameStr == "") then
        classNameStr = nil;
    end
    local armourType = classNameStr and SafeCalc(classNameStr .. "CDArmourType", level) or nil;
    local armourName = ARMOUR_NAMES[armourType or 2] or "Medium";

    header:SetText(T(string.format("Level %d %s  (%s armour)", level, classNameStr or "?", armourName)));

    local samples = {};
    local y = PAD_TOP + ROW_H;
    for index, def in ipairs(ROWS) do
        local w = rowWidgets[index];
        if (def.section) then
            w.title:SetPosition(PAD_X, y);
            w.title:SetVisible(true);
            y = y + SECTION_H;
        else
            local ok, rating = pcall(def.get, attributes);
            local valid = ok and type(rating) == "number";
            if (not valid and not def.readError) then
                Turbine.Shell.WriteLine("StatCaps: cannot read " .. def.label .. ": " .. tostring(rating));
            end
            def.readError = not valid;
            rating = valid and rating or 0;
            local canUse = true;
            if (def.can) then
                local canOk, can = pcall(attributes[def.can], attributes);
                canUse = canOk and can;
            end
            local prefix = def.stat == "Mit" and ("Mit" .. armourName) or def.stat;
            local tier = selectedTier == 1 and 0 or selectedTier - 1;
            local limit, effective, cap = StatCapsRatings.Calculate(
                CalcStat, def.stat, prefix, level, tier, rating);
            if (canUse) then
                samples[def.key or def.stat] = {
                    label = def.label, rating = rating, limit = limit, valid = valid
                };
            end

            if (not canUse or not limit or (def.hideZero and rating <= 0)) then
                SetRowVisible(w, false);
            else
                local ratio = rating / limit;
                local color = ColorFor(ratio);
                local pctText = "";
                if (effective and cap) then
                    pctText = string.format("%.1f / %.0f%%", effective, cap);
                end

                w.background:SetPosition(PAD_X, y);
                w.name:SetPosition(COL[1].x, y);
                w.rating:SetPosition(COL[2].x, y);
                w.limit:SetPosition(COL[3].x, y);
                w.diff:SetPosition(COL[4].x, y);
                w.pct:SetPosition(COL[5].x, y);
                w.track:SetPosition(PAD_X, y + ROW_H - 5);
                w.bar:SetPosition(PAD_X, y + ROW_H - 5);

                w.rating:SetText(valid and Fmt(rating) or "N/A");
                w.limit:SetText(Fmt(limit));
                w.diff:SetText(valid and FmtSigned(rating - limit) or "N/A");
                w.diff:SetForeColor(color);
                w.pct:SetText(valid and pctText or "N/A");
                w.pct:SetForeColor(color);
                w.bar:SetBackColor(color);
                w.bar:SetWidth(math.max(1, math.floor(BAR_W * math.min(ratio, 1))));
                SetRowVisible(w, true);
                y = y + ROW_H;
            end
        end
    end
    local attributeValues = {};
    for _, name in ipairs({ "Might", "Agility", "Vitality", "Will", "Fate" }) do
        local ok, value = pcall(function() return attributes["Get" .. name](attributes); end);
        if (ok and type(value) == "number") then
            attributeValues[name] = value;
            attributeReadErrors[name] = nil;
        elseif (not attributeReadErrors[name]) then
            attributeReadErrors[name] = true;
            Turbine.Shell.WriteLine("StatCaps: cannot read main attribute " .. name .. ": " .. tostring(value));
        end
    end
    local moraleOk, morale = pcall(function() return player:GetMaxMorale(); end);
    local armourOk, armour = pcall(function() return attributes:GetArmor(); end);
    currentSnapshot = StatCapsComparison.Capture(samples, attributeValues,
        moraleOk and type(morale) == "number" and morale or nil,
        armourOk and type(armour) == "number" and armour or nil);
    currentSnapshot.level = level;
    if (classNameStr) then SaveCharacterProfile(classNameStr); end
    UpdateAdvice(classNameStr, samples, attributeValues);

    footer:SetPosition(PAD_X, y + 4);
    footer:SetSize(BAR_W, 64);
    footer:SetText(T(tierNames[selectedTier] .. ": same-level enemies; Landscape and normal T1 share caps.\n"
        .. "T2/T3 include mitigation, BPE and resistance penetration.\n"
        .. "Boss levels, special debuffs and some raids need different targets."));
    footer:SetVisible(true);
    for _, t in ipairs(columnTitles) do
        t:SetPosition(t:GetLeft(), PAD_TOP);
        t:SetVisible(true);
    end

    local height = y + 4 + 64 + 18;
    if (win:GetHeight() ~= height) then
        resizeMainPanel(WIN_W, height);
    end
end

local tierButtons = {};
local function UpdateTierButtons()
    for index, button in ipairs(tierButtons) do
        button:SetSelected(index == selectedTier);
        button:SetText(T((index == selectedTier and "> " or "") .. tierNames[index]));
    end
end
for index, name in ipairs(tierNames) do
    local choice = index;
    local button = StatCapsMainSkin.Button(win, name, PAD_X + (index - 1) * 132, 86, "tier");
    button:SetVisible(true);
    button.Click = function()
        selectedTier = choice;
        UpdateTierButtons();
        Refresh();
        SaveSettings();
    end
    tierButtons[index] = button;
end
UpdateTierButtons();

local icon = Turbine.UI.Window(); -- parentless controls are not rendered, so the icon needs its own window
do
    local ICON_SIZE = 32;
    icon:SetSize(ICON_SIZE, ICON_SIZE);
    icon:SetBackColor(Turbine.UI.Color(0.65, 0.54, 0.32));
    local iconText = Turbine.UI.Label();
    iconText:SetParent(icon);
    iconText:SetPosition(2, 2);
    iconText:SetSize(ICON_SIZE - 4, ICON_SIZE - 4);
    iconText:SetBackColor(Turbine.UI.Color(0.055, 0.06, 0.065));
    iconText:SetForeColor(Turbine.UI.Color(0.95, 0.85, 0.5));
    iconText:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    iconText:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    iconText:SetText("SC");
    iconText:SetMouseVisible(false);
    for _, y in ipairs({ 4, ICON_SIZE - 5 }) do
        local ornament = Turbine.UI.Control();
        ornament:SetParent(icon);
        ornament:SetPosition(12, y);
        ornament:SetSize(8, 1);
        ornament:SetBackColor(Turbine.UI.Color(0.65, 0.54, 0.32));
        ornament:SetMouseVisible(false);
    end
    icon:SetZOrder(-1);
    icon:SetPosition(
        math.max(0, math.min(tonumber(settings.iconX) or math.floor(dispW * 0.7), dispW - ICON_SIZE)),
        math.max(0, math.min(tonumber(settings.iconY) or math.floor(dispH * 0.2) - 40, dispH - ICON_SIZE)));
    icon:SetVisible(true);
    icon:SetWantsKeyEvents(false);

    local dragging, moved, startMouseX, startMouseY, startLeft, startTop;
    icon.MouseDown = function(_, args)
        dragging, moved = true, false;
        startMouseX, startMouseY = Turbine.UI.Display.GetMousePosition();
        startLeft, startTop = icon:GetLeft(), icon:GetTop();
    end
    icon.MouseMove = function()
        if (not dragging) then
            return;
        end
        local mx, my = Turbine.UI.Display.GetMousePosition();
        local dx, dy = mx - startMouseX, my - startMouseY;
        if (moved or math.abs(dx) + math.abs(dy) > 4) then
            moved = true;
            icon:SetPosition(
                math.max(0, math.min(startLeft + dx, dispW - ICON_SIZE)),
                math.max(0, math.min(startTop + dy, dispH - ICON_SIZE)));
        end
    end
    icon.MouseUp = function()
        if (not dragging) then
            return;
        end
        dragging = false;
        if (moved) then
            SaveSettings();
        else
            win:SetVisible(not win:IsVisible());
            if (win:IsVisible()) then win:Activate(); end
        end
    end
end

SaveSettings = function()
    settings.x = math.floor(win:GetLeft());
    settings.y = math.floor(win:GetTop());
    settings.iconX = math.floor(icon:GetLeft());
    settings.iconY = math.floor(icon:GetTop());
    settings.tier = tostring(selectedTier);
    settings.build = selectedBuild;
    local ok, err = pcall(Turbine.PluginData.Save, Turbine.DataScope.Character, SETTINGS_KEY, settings);
    if (not ok) then
        Turbine.Shell.WriteLine("StatCaps: could not save settings: " .. tostring(err));
    end
end

local virtueLog = false;
local function AddCallback(object, event, callback)
    if (object[event] == nil) then
        object[event] = callback;
    elseif (type(object[event]) == "table") then
        table.insert(object[event], callback);
    else
        object[event] = { object[event], callback };
    end
end
local function RemoveCallback(object, event, callback)
    local handlers = object[event];
    if (type(handlers) == "function") then
        if (handlers == callback) then object[event] = nil; end
    elseif (type(handlers) == "table") then
        for index = #handlers, 1, -1 do
            if (handlers[index] == callback) then table.remove(handlers, index); end
        end
    end
end
local chatHandler = function(_, args)
    if (not args or type(args.Message) ~= "string" or not Turbine.ChatType) then return; end
    local advancement = args.ChatType == Turbine.ChatType.Advancement;
    local standard = args.ChatType == Turbine.ChatType.Standard;
    if (not advancement and not standard) then return; end
    if (virtueLog and not args.Message:find("[StatCaps virtue log]", 1, true)) then
        local lower = args.Message:lower();
        local relevant = lower:find("virtue", 1, true);
        if (not relevant) then
            for _, virtue in ipairs(StatCapsVirtueData.virtues) do
                if (lower:find(virtue.name:lower(), 1, true)) then relevant = true; break; end
            end
        end
        if (advancement or relevant) then
            Turbine.Shell.WriteLine("[StatCaps virtue log] " .. args.Message);
        end
    end
    local name, rank = StatCapsVirtues.ParseRankMessage(args.Message);
    if (not name or not StatCapsVirtues.UpdateRank(settings.virtueRanks, name, rank)) then return; end
    if (type(settings.virtues) == "table") then
        local limits = StatCapsVirtues.Limits(player:GetLevel());
        for _, choice in pairs(settings.virtues) do
            if (type(choice) == "table" and choice.name == name and limits) then
                choice.rank = math.min(rank, limits.rank);
            end
        end
    end
    SaveSettings();
    if (virtueWin) then virtueWin.RanksChanged(name, rank); end
    Turbine.Shell.WriteLine(T("StatCaps: saved ") .. name .. T(" rank ") .. rank .. ".");
end
if (Turbine.Chat) then
    AddCallback(Turbine.Chat, "Received", chatHandler);
else
    Turbine.Shell.WriteLine(T("StatCaps: chat event unavailable; virtue rank-ups need manual correction."));
end

local ticker = Turbine.UI.Control();
local nextRefresh = 0;
ticker:SetWantsUpdates(true);
ticker.Update = function()
    local visible = win:IsVisible() or adviceWin:IsVisible();
    local now = Turbine.Engine.GetGameTime();
    if (now >= nextRefresh) then
        nextRefresh = now + (visible and REFRESH_SECONDS or 60);
        local ok, err = pcall(Refresh);
        if (not ok) then
            Turbine.Shell.WriteLine(T("StatCaps error: ") .. T(tostring(err)));
            nextRefresh = now + 30;
        end
    end
end

local skinVisibilityChanged = win.VisibleChanged;
win.VisibleChanged = function()
    skinVisibilityChanged();
    if (win:IsVisible()) then
        nextRefresh = 0;
    else
        SaveSettings();
    end
    icon:SetZOrder(-1);
end

local command = Turbine.ShellCommand();
local function PrintDiagnostics()
    local function line(label, value)
        local text = tostring(value):gsub("[%c]", " "):sub(1, 500);
        Turbine.Shell.WriteLine("[StatCaps] " .. T(label) .. ": " .. text);
    end
    local function read(label, getter)
        local ok, value = pcall(getter);
        if (not ok or value == nil) then
            line(label, T("Unavailable") .. " - " .. tostring(value));
        else
            line(label, value);
        end
    end
    line("Diagnostics", "StatCaps 1.0 Beta");
    read("Client language", function()
        local language = Turbine.Engine.GetLanguage();
        for _, name in ipairs({ "English", "German", "French" }) do
            if (Turbine.Language and Turbine.Language[name] ~= nil and language == Turbine.Language[name]) then
                return T(name);
            end
        end
        return language and (T("Unknown") .. " (" .. tostring(language) .. ")") or nil;
    end);
    line("Interface language", StatCapsLocalization.Locale());
    read("Character level", function() return player:GetLevel(); end);
    read("Detected class", function()
        local id = player:GetClass();
        if (not hasCalcStat) then return tostring(id) .. " - " .. T("CalcStat unavailable"); end
        local name = CalcStat("ClassName", id);
        assert(type(name) == "string" and name ~= "", "Unknown class");
        return T(name) .. " (" .. tostring(id) .. ")";
    end);
    line("CalcStat", T(hasCalcStat and "Available" or "Unavailable"));
    line("Last item lookup/link issue", T(StatCapsManual.LastItemIssue or "None recorded this session"));
end
function command:GetShortHelp()
    return T("/statcaps [show|hide|virtuelog] - toggle window; virtuelog toggles advancement diagnostics");
end
function command:GetHelp()
    return self:GetShortHelp() .. "\n" ..
        T("/statcaps item <item link or ID> - open the replacement item search") .. "\n" ..
        T("/statcaps debug - print a one-time diagnostic report in chat") .. "\n" ..
        T("/statcaps loadout - compare a full planned equipment loadout") .. "\n" ..
        T("/statcaps settings - open appearance and utilities");
end
local optionsWin;
local function OpenSettings()
    if (optionsWin) then
        optionsWin:SetVisible(true);
        optionsWin:Activate();
        return;
    end
    optionsWin = StatCapsTheme.Window();
    optionsWin:SetText(T("Stat Caps - Settings"));
    optionsWin:SetSize(460, 610);
    StatCapsTheme.Panel(optionsWin, 460, 610);
    optionsWin:SetPosition(math.max(0, (dispW - 460) / 2), math.max(0, (dispH - 610) / 2));
    local function label(text, y, height)
        local value = Turbine.UI.Label();
        value:SetParent(optionsWin);
        value:SetPosition(22, y);
        value:SetSize(416, height);
        value:SetFont(FONT_SMALL);
        value:SetForeColor(Turbine.UI.Color(0.92, 0.9, 0.84));
        value:SetText(T(text));
        return value;
    end
    label("Appearance", 42, 22):SetForeColor(Turbine.UI.Color(0.93, 0.83, 0.6));
    local status = label("Appearance changes apply after reloading StatCaps.", 300, 88);
    local preview = Turbine.UI.Control();
    preview:SetParent(optionsWin);
    preview:SetPosition(22, 69);
    preview:SetSize(416, 68);
    preview:SetMouseVisible(false);
    local previewText = label("", 116, 52);
    previewText:SetPosition(100, 78);
    previewText:SetSize(330, 52);
    previewText:SetMouseVisible(false);
    local previewBadge = Turbine.UI.Control();
    previewBadge:SetParent(optionsWin);
    previewBadge:SetPosition(404, 106);
    previewBadge:SetSize(28, 28);
    previewBadge:SetMouseVisible(false);
    if (type(settings.theme) ~= "table") then settings.theme = {}; end
    local selectors = {};
    local function updateThemeChoices()
        local pending = StatCapsThemeProfiles.Resolve(settings.theme, player,
            Turbine.Gameplay, hasCalcStat and CalcStat or nil);
        preview:SetBackground("StatCaps/Resources/" .. pending.folder .. "main_header.tga");
        previewText:SetText(T(pending.race) .. (pending.class and (" / " .. T(pending.class)) or "") ..
            "\n" .. T("Preview - applies after reload"));
        previewBadge:SetVisible(pending.class ~= nil);
        if (pending.class) then
            previewBadge:SetBackground("StatCaps/Resources/class_" .. pending.class .. ".tga");
        end
        for _, selector in ipairs(selectors) do
            local value = settings.theme[selector.key] or selector.default;
            selector.value:SetText(T(value));
        end
        if (pending.warning) then
            status:SetText(T(pending.warning) .. "\n" .. T("Appearance changes apply after reloading StatCaps."));
        end
    end
    local function saveThemeChoice()
        SaveSettings();
        status:SetText(T("Appearance saved. Reload with:") ..
            "\n/plugins unload StatCaps\n/plugins load StatCaps");
        updateThemeChoices();
    end
    local function selector(key, title, values, default, y)
        local caption = label(title, y + 5, 22);
        caption:SetSize(132, 22);
        local current = label("", y + 5, 22);
        current:SetPosition(193, y + 5);
        current:SetSize(203, 22);
        current:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
        local previous, nextChoice = StatCapsTheme.Button(), StatCapsTheme.Button();
        for index, button in ipairs({ previous, nextChoice }) do
            button:SetParent(optionsWin);
            button:SetPosition(index == 1 and 158 or 404, y);
            button:SetSize(32, 28);
            button:SetText(index == 1 and "<" or ">");
            button.Click = function()
                local position = 1;
                for i, value in ipairs(values) do
                    if (value == (settings.theme[key] or default)) then position = i; end
                end
                position = (position - 1 + (index == 1 and -1 or 1)) % #values + 1;
                settings.theme[key] = values[position];
                saveThemeChoice();
            end;
        end
        selectors[#selectors + 1] = { key = key, default = default, value = current,
            previous = previous, next = nextChoice };
    end
    local races, classes = { "Automatic" }, { "Automatic" };
    for _, name in ipairs(StatCapsThemeProfiles.Races) do races[#races + 1] = name; end
    for _, name in ipairs(StatCapsThemeProfiles.Classes) do classes[#classes + 1] = name; end
    selector("race", "Race design", races, "Automatic", 146);
    selector("class", "Class accent", classes, "Automatic", 182);
    updateThemeChoices();
    local function utility(text, y, handler)
        local button = StatCapsTheme.Button();
        button:SetParent(optionsWin);
        button:SetPosition(22, y);
        button:SetSize(416, 28);
        button:SetText(T(text));
        button.Click = handler;
    end
    utility("Scoring", 414, function()
        local context, err = PlanningContext();
        if (not context) then status:SetText(T(err)); return; end
        scoringButton.Click();
    end);
    utility("Compare loadouts", 450, function() OpenLoadouts(); end);
    utility("Diagnostics", 486, PrintDiagnostics);
    utility("Command help", 522, function() Turbine.Shell.WriteLine(command:GetHelp()); end);
    label("Scoring uses the build selected in Build advice.", 564, 30);
    optionsWin:SetVisible(true);
    optionsWin:Activate();
end
do
    local button = StatCapsTheme.Button();
    button:SetParent(win);
    button:SetPosition(410, 12);
    button:SetSize(86, 28);
    button:SetText(T("Settings"));
    button.Click = OpenSettings;
end
function command:Execute(_, args)
    local linkedItem = (args or ""):match("^%s*[Ii][Tt][Ee][Mm]%s+(.+)%s*$");
    if (linkedItem) then
        manualButton.Click();
        manualWin.OpenItemLink(linkedItem);
        return;
    end
    local action = string.lower(string.gsub(args or "", "^%s*(.-)%s*$", "%1"));
    if (action == "settings") then
        OpenSettings();
    elseif (action == "loadout") then
        OpenLoadouts();
    elseif (action == "debug") then
        PrintDiagnostics();
    elseif (action == "show") then
        win:SetVisible(true);
        win:Activate();
    elseif (action == "hide") then
        win:SetVisible(false);
    elseif (action == "virtuelog") then
        virtueLog = not virtueLog;
        Turbine.Shell.WriteLine(T("StatCaps: advancement message logging ") ..
            T(virtueLog and "ON" or "OFF") .. T(". Use /statcaps virtuelog to toggle."));
    else
        win:SetVisible(not win:IsVisible());
        if (win:IsVisible()) then win:Activate(); end
    end
end
Turbine.Shell.AddCommand("statcaps", command);

plugin.Unload = function()
    ticker:SetWantsUpdates(false);
    if (hasCalcStat and currentSnapshot) then
        local refreshed, refreshError = pcall(Refresh);
        if (not refreshed) then
            Turbine.Shell.WriteLine("StatCaps: could not refresh the final character snapshot: " .. tostring(refreshError));
        end
        local ok, className = pcall(CalcStat, "ClassName", player:GetClass());
        if (ok and type(className) == "string") then SaveCharacterProfile(className, true); end
    end
    SaveSettings();
    adviceWin:SetVisible(false);
    if (manualWin) then manualWin:SetVisible(false); end
    if (loadoutWin) then loadoutWin.HideChildren(); loadoutWin:SetVisible(false); end
    if (scoringWin) then scoringWin:SetVisible(false); end
    if (virtueWin) then virtueWin.HideChildren(); virtueWin:SetVisible(false); end
    if (optionsWin) then optionsWin:SetVisible(false); end
    if (Turbine.Chat) then RemoveCallback(Turbine.Chat, "Received", chatHandler); end
    Turbine.Shell.RemoveCommand(command);
end

win:SetVisible(true);
icon:SetZOrder(-1);
Turbine.Shell.WriteLine(T("StatCaps loaded. Click the SC icon or type /statcaps to show/hide the window."));
