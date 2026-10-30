StatCapsScoring = {};

local function T(text)
    return StatCapsLocalization.Text(text);
end
StatCapsScoring.ScoreTolerance = 0.000000001;
StatCapsScoring.DisplayScale = 1000;

function StatCapsScoring.ScoreState(score)
    if (score > StatCapsScoring.ScoreTolerance) then return "UPGRADE"; end
    if (score < -StatCapsScoring.ScoreTolerance) then return "DOWNGRADE"; end
    return "NEUTRAL";
end

function StatCapsScoring.FormatScore(score)
    local displayed = score * StatCapsScoring.DisplayScale;
    if (math.abs(displayed) > StatCapsScoring.ScoreTolerance * StatCapsScoring.DisplayScale
        and math.abs(displayed) < 0.01) then
        return string.format("%+.6g", displayed);
    end
    return string.format("%+.2f", displayed);
end

StatCapsScoring.Fields = {
    { "Fate", "Fate", 501 },
    { "Vitality", "Vitality", 595 },
    { "Morale", "Maximum Morale" },
    { "CritHit", "Critical Rating", 5530 },
    { "PhysicalMastery", "Physical Mastery", 4589 },
    { "TacticalMastery", "Tactical Mastery", 4589 },
    { "Finesse", "Finesse", 7337 },
    { "OutHeal", "Outgoing Healing", 12694 },
    { "PhysicalMitigation", "Physical Mitigation", 4436 },
    { "TacticalMitigation", "Tactical Mitigation", 4436 },
    { "Armour", "Armour" },
    { "Block", "Block", 7716 },
    { "Parry", "Parry", 7716 },
    { "Evade", "Evade", 7716 },
    { "Resist", "Resistance", 9969 },
    { "InHeal", "Incoming Healing", 7337 },
    { "CritDef", "Critical Defence", 7337 }
};

function StatCapsScoring.Key(className, role)
    return className .. ":" .. role;
end

function StatCapsScoring.EffectiveWeight(classWeight, roleValue)
    return (classWeight * 5 + roleValue / 5) / 6;
end

-- Columns follow the supplied sheet: Fate through Critical Defence.
local presetColumns = { "Fate", "Vitality", "Morale", "CritHit", "PhysicalMastery",
    "TacticalMastery", "Finesse", "OutHeal", "PhysicalMitigation", "TacticalMitigation",
    "Armour", "Block", "Parry", "Evade", "Resist", "InHeal", "CritDef" };
local physicalDD = { 0, 80, 0, 100, 100, 0, 100, 0, 100, 100, 0, 0, 0, 0, 0, 0, 0 };
local tacticalDD = { 0, 80, 0, 100, 0, 100, 100, 0, 100, 100, 0, 0, 0, 0, 0, 0, 0 };
local healer = { 0, 80, 0, 100, 0, 36.15, 0, 100, 100, 100, 0, 0, 0, 0, 0, 0, 0 };
local tank = { 0, 100, 0, 0, 0, 0, 0, 0, 100, 100, 0, 50, 50, 50, 0, 67, 33 };
local sheetPresets = {
    Beorning = {
        Blue = { 18.71, 100, 0, 0, 0, 9.04, 100, 25, 100, 100, 0, 50, 50, 50, 0, 67, 33 },
        Red = { 14.97, 80, 0, 100, 100, 0, 100, 0, 100, 100, 0, 0, 0, 0, 0, 0, 0 },
        Yellow = { 14.97, 80, 0, 100, 100, 36.15, 100, 100, 100, 100, 0, 0, 0, 0, 0, 0, 0 }
    },
    Brawler = { Blue = tank, Red = physicalDD },
    Captain = { Blue = healer, Red = physicalDD,
        Yellow = { 0, 100, 0, 0, 0, 18.08, 0, 50, 100, 100, 0, 50, 50, 50, 0, 67, 33 } },
    Champion = { Blue = tank, Red = physicalDD, Yellow = physicalDD },
    Guardian = {
        Blue = { 0, 100, 0, 0, 0, 0, 100, 0, 100, 100, 0, 67, 67, 67, 0, 67, 25 },
        Red = physicalDD
    },
    Burglar = { Blue = physicalDD, Red = physicalDD, Yellow = physicalDD },
    Hunter = { Blue = physicalDD, Red = physicalDD, Yellow = physicalDD },
    Mariner = { Blue = physicalDD, Red = physicalDD, Yellow = physicalDD },
    Warden = {
        Blue = { 0, 100, 0, 100, 0, 36.15, 100, 100, 100, 100, 0, 67, 67, 67, 0, 67, 25 },
        Red = physicalDD
    },
    LoreMaster = { Blue = tacticalDD, Red = tacticalDD,
        Yellow = { 0, 80, 0, 100, 0, 100, 100, 100, 100, 100, 0, 0, 0, 0, 0, 0, 0 } },
    Minstrel = { Blue = healer, Red = tacticalDD },
    RuneKeeper = { Blue = healer, Red = tacticalDD, Yellow = tacticalDD }
};

local defaultColours = {
    Beorning = { DD = "Red", Tank = "Blue", Heal = "Yellow" },
    Brawler = { DD = "Red", Tank = "Blue" },
    Burglar = { DD = "Red", Support = "Yellow" },
    Captain = { DD = "Red", Tank = "Yellow", Heal = "Blue", Support = "Red" },
    Champion = { DD = "Red", Tank = "Blue" },
    Guardian = { DD = "Red", Tank = "Blue" },
    Hunter = { DD = "Red" },
    LoreMaster = { DD = "Red", Support = "Yellow" },
    Mariner = { DD = "Red", Support = "Yellow" },
    Minstrel = { DD = "Red", Heal = "Blue" },
    RuneKeeper = { DD = "Red", Heal = "Blue" },
    Warden = { DD = "Red", Tank = "Blue" }
};

local roleMultiplierDefaults = {
    DD = {
        PhysicalMitigation = 1, TacticalMitigation = 2, Morale = 1,
        ClassDamageMastery = 5, CritHit = 4, OutHeal = 0, InHeal = 0,
        Resist = 0, CritDef = 0, Finesse = 2, Block = 0, Parry = 0, Evade = 0
    },
    Tank = {
        PhysicalMitigation = 5, TacticalMitigation = 5, Morale = 5,
        ClassDamageMastery = 0, CritHit = 0, OutHeal = 0, InHeal = 2,
        Resist = 0, CritDef = 1, Finesse = 0, Block = 1, Parry = 1, Evade = 1
    },
    Heal = {
        PhysicalMitigation = 5, TacticalMitigation = 5, Morale = 5,
        ClassDamageMastery = 0, CritHit = 4, OutHeal = 5, InHeal = 0,
        Resist = 0, CritDef = 0, Finesse = 0, Block = 0, Parry = 0, Evade = 0
    },
    Support = {
        PhysicalMitigation = 5, TacticalMitigation = 5, Morale = 5,
        ClassDamageMastery = 1, CritHit = 4, OutHeal = 0, InHeal = 0,
        Resist = 0, CritDef = 0.5, Finesse = 5, Block = 0, Parry = 0, Evade = 0
    }
};

function StatCapsScoring.RoleWeights(profile, overrides)
    if (not profile or not roleMultiplierDefaults[profile.role]) then
        return nil, "No role value defaults are available for this build.";
    end
    local defaults = roleMultiplierDefaults[profile.role];
    local result = {};
    for _, field in ipairs(StatCapsScoring.Fields) do
        local key = field[1];
        result[key] = key == profile.damage and defaults.ClassDamageMastery or defaults[key] or 0;
    end
    if (type(overrides) == "table") then
        for key, value in pairs(overrides) do
            result[key] = value;
        end
    end
    return result;
end

function StatCapsScoring.Default(profile, calc)
    local colour = defaultColours[profile.className] and defaultColours[profile.className][profile.role];
    if (not colour) then return nil, "No class/build EV default is available."; end
    local config, err = StatCapsScoring.Preset(profile.className, colour, calc);
    if (not config) then return nil, err; end
    config.roleWeights = assert(StatCapsScoring.RoleWeights(profile));
    return config;
end

function StatCapsScoring.Resolve(profile, config, calc)
    if (not profile) then return; end
    local err;
    if (not config) then config, err = StatCapsScoring.Default(profile, calc); end
    if (not config) then profile.scoringError = err; return profile; end
    StatCapsScoring.Apply(profile, config);
    if (not profile.scoringError) then StatCapsAdvice.ScoringPriorities(profile); end
    return profile;
end

function StatCapsScoring.Preset(className, colour, calc)
    local row = sheetPresets[className] and sheetPresets[className][colour];
    if (not row) then return nil, "No " .. colour .. " EV preset for this class in the supplied table."; end
    if (type(calc) ~= "function") then return nil, "CalcStat is required for the Vitality-to-morale reference."; end
    local vitalityMorale = calc(className .. "CDVitalityToMorale", 1);
    if (type(vitalityMorale) ~= "number" or vitalityMorale <= 0) then
        return nil, "Vitality-to-morale conversion is unavailable for this class.";
    end
    local config = { mode = "essence", weights = {}, references = {}, preset = colour .. " " .. className };
    for _, field in ipairs(StatCapsScoring.Fields) do
        config.weights[field[1]] = 0;
        config.references[field[1]] = field[3];
    end
    for index, key in ipairs(presetColumns) do config.weights[key] = row[index] / 100; end
    config.references.Morale = 595 * vitalityMorale;
    if (className == "Warden" and colour == "Blue") then config.weights.Morale = 1; end
    return config;
end

function StatCapsScoring.Validate(mode, weights, references, metadata)
    if (mode ~= "cap" and mode ~= "essence") then return nil, "Choose a scoring mode."; end
    local result = { mode = mode, weights = {}, references = {} };
    if (metadata and metadata.finesseTarget ~= nil and metadata.finesseTarget ~= "") then
        local target = tonumber(metadata.finesseTarget);
        if (not target or target ~= target or target < 0 or target > 50) then
            return nil, "Finesse target: enter a percentage from 0 to 50, or leave blank to exclude Finesse.";
        end
        result.finesseTarget = target;
    end
    if (metadata and metadata.preset) then
        if (type(metadata.preset) ~= "string") then return nil, "Invalid EV preset; reload a class preset."; end
        result.preset = metadata.preset;
    end
    if (metadata and metadata.roleWeights ~= nil) then
        if (type(metadata.roleWeights) ~= "table") then return nil, "Role values must be a table."; end
        result.roleWeights = {};
        for _, field in ipairs(StatCapsScoring.Fields) do
            local key = field[1];
            local rawMultiplier = metadata.roleWeights[key];
            local multiplier = rawMultiplier == nil and 0 or tonumber(rawMultiplier);
            if (not multiplier or multiplier ~= multiplier or multiplier < 0 or multiplier > 10) then
                return nil, field[2] .. ": role value must be a number from 0 to 10.";
            end
            result.roleWeights[key] = multiplier;
        end
    end
    for _, field in ipairs(StatCapsScoring.Fields) do
        local key, label = field[1], field[2];
        local rawWeight = weights[key];
        local weight = rawWeight == nil and 0 or tonumber(rawWeight);
        if (not weight or weight ~= weight or weight < 0 or weight > 100) then
            return nil, label .. ": weight must be a number from 0 to 100.";
        end
        result.weights[key] = weight;
        local raw = references[key];
        local reference = tonumber(raw);
        if (raw ~= nil and raw ~= "" and (not reference or reference ~= reference or reference <= 0 or reference > 1000000000)) then
            return nil, label .. ": amount per essence must be greater than 0 and at most 1000000000.";
        end
        local roleValue = result.roleWeights and result.roleWeights[key] or 0;
        if (mode == "essence" and StatCapsScoring.EffectiveWeight(weight, roleValue) > 0 and not reference) then
            return nil, label .. ": enter an amount per essence, or set its combined weight to 0.";
        end
        result.references[key] = reference;
    end
    return result;
end

function StatCapsScoring.Apply(profile, config)
    if (not profile or not config) then return profile; end
    if (not config.roleWeights) then
        local defaults, roleError = StatCapsScoring.RoleWeights(profile);
        if (not defaults) then profile.scoringError = roleError; return profile; end
        local upgraded = {};
        for key, value in pairs(config) do upgraded[key] = value; end
        upgraded.roleWeights = defaults;
        config = upgraded;
    end
    local validated, err = StatCapsScoring.Validate(config.mode, config.weights or {}, config.references or {}, config);
    if (not validated) then profile.scoringError = "Scoring settings invalid: " .. err; return profile; end
    profile.scoring = validated;
    return profile;
end

function StatCapsScoring.Reference(profile, key, fallback)
    if (key == "Fate" or key == "Vitality" or key == "Armour") then
        if (profile.scoring and profile.scoring.mode == "essence") then
            return profile.scoring.references[key], 1;
        end
        return (profile.scoring and profile.scoring.references[key]) or fallback, 100;
    end
    if (profile.scoring and profile.scoring.mode == "essence") then
        return profile.scoring.references[key], 1;
    end
    return fallback, 100;
end

function StatCapsScoring.Limit(profile, key, sample, level)
    if (key ~= "Finesse" or not profile.scoring) then return sample.limit; end
    local target = profile.scoring.finesseTarget;
    if (target == nil or target == 0) then return 0; end
    if (type(level) ~= "number" or level % 1 ~= 0 or level < 1 or level > 160) then
        return nil, "Finesse target requires a supported character level.";
    end
    local rating = CalcStat("FinessePPRat", level, target);
    if (type(rating) ~= "number" or rating ~= rating or rating <= 0) then
        return nil, "Finesse target rating could not be calculated.";
    end
    return math.min(sample.limit, rating);
end

function StatCapsScoring.AdviceSamples(profile, samples, level)
    if (not profile.scoring or profile.scoring.finesseTarget == nil or not samples.Finesse) then return samples; end
    local limit, err = StatCapsScoring.Limit(profile, "Finesse", samples.Finesse, level);
    if (not limit) then return nil, err; end
    local adjusted = {};
    for key, sample in pairs(samples) do adjusted[key] = sample; end
    local original = samples.Finesse;
    adjusted.Finesse = { label = "Finesse (chosen " .. profile.scoring.finesseTarget .. "% target)",
        rating = original.rating, valid = original.valid, limit = limit, hardLimit = original.limit };
    return adjusted;
end

function StatCapsScoring.Description(profile)
    local finesse = "";
    if (profile.scoring) then
        finesse = profile.scoring.finesseTarget ~= nil
            and (" Finesse stops at your chosen " .. profile.scoring.finesseTarget .. "% target.")
            or " Finesse excluded until an encounter target is set.";
    end
    if (profile.scoring and profile.scoring.mode == "essence") then
        return (profile.scoring.preset and profile.scoring.preset .. " EV preset (editable). " or "") ..
            "Essence-equivalent: useful amount / amount per essence x ((class EV x 5 + role value / 5) / 6). Ratings still clip at caps." .. finesse;
    end
    return "Cap-normalized: 1% of a rating cap earns (class EV x 5 + role value / 5) / 6; morale uses 1% of current maximum." .. finesse;
end

function StatCapsScoring.Open(profile, config, save, calc)
    local defaultError;
    if (not config and calc) then config, defaultError = StatCapsScoring.Default(profile, calc); end
    if (not config) then
        config = { weights = {}, references = {}, roleWeights = StatCapsScoring.RoleWeights(profile) or {} };
        defaultError = defaultError or "Cannot load class EV values without CalcStat.";
    end
    if (config and not config.roleWeights) then
        config = {
            mode = config.mode, weights = config.weights, references = config.references,
            preset = config.preset,
            finesseTarget = config.finesseTarget,
            roleWeights = StatCapsScoring.RoleWeights(profile)
        };
    end
    local win = StatCapsTheme.Window();
    win:SetText(T("Stat Caps - Scoring / " .. profile.name));
    win:SetSize(760, 760);
    StatCapsTheme.Panel(win, 760, 760);
    local width, height = Turbine.UI.Display.GetSize();
    win:SetPosition(math.max(0, (width - 760) / 2), math.max(0, (height - 760) / 2));
    local function label(text, x, y, w, h)
        local control = Turbine.UI.Label();
        control:SetParent(win);
        control:SetPosition(x, y);
        control:SetSize(w, h);
        control:SetFont(Turbine.UI.Lotro.Font.Verdana14);
        control:SetForeColor(Turbine.UI.Color(0.92, 0.9, 0.84));
        control:SetText(T(text));
        return control;
    end
    label("Changes affect " .. profile.name ..
        " scores and priorities at all levels, not your character's stats.\n" ..
        "Reset removes this build's saved custom scoring.", 20, 38, 710, 45);
    local mode = config and config.mode or "cap";
    local metadata = config;
    local cap, essence = StatCapsTheme.Button(), StatCapsTheme.Button();
    local referenceHeader, referenceInputs, loadAmountsButton, modeHelp;
    local function modes()
        cap:SetText(T(mode == "cap" and "> Cap-normalized" or "Cap-normalized"));
        essence:SetText(T(mode == "essence" and "> Essence-equivalent" or "Essence-equivalent"));
        if (referenceHeader) then referenceHeader:SetVisible(mode == "essence"); end
        for _, input in ipairs(referenceInputs or {}) do input:SetVisible(mode == "essence"); end
        if (loadAmountsButton) then loadAmountsButton:SetVisible(mode == "essence"); end
        if (modeHelp) then
            modeHelp:SetText(T(mode == "cap"
                and "Cap mode compares each rating with its level/tier limit.\nEssence amounts are not used in this mode."
                or "Each value is how many points of that stat equal one essence; it isn't a cap.\nLoad sheet amounts fills these values; half earns half the stat's final weight."));
        end
    end
    for index, button in ipairs({ cap, essence }) do
        button:SetParent(win);
        button:SetPosition(20 + (index - 1) * 290, 95);
        button:SetSize(280, 26);
    end
    cap.Click = function() mode = "cap"; modes(); end
    essence.Click = function() mode = "essence"; modes(); end
    modeHelp = label("", 20, 125, 710, 42);
    modeHelp:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    modes();
    label("Class EV preset:", 20, 170, 150, 24);
    label("Stat", 20, 203, 180, 22);
    label("Class EV", 205, 203, 80, 22);
    label("Role value", 300, 203, 90, 22);
    referenceHeader = label("Amount per essence", 400, 203, 200, 22);
    local inputs = {};
    referenceInputs = {};
    local defaults = config.weights;
    if (not defaults or not next(defaults)) then
        defaults = profile.scoring and profile.scoring.weights or StatCapsAdvice.Weights(profile);
    end
    local roleDefaults = config.roleWeights or StatCapsScoring.RoleWeights(profile) or {};
    for index, field in ipairs(StatCapsScoring.Fields) do
        local y = 225 + (index - 1) * 20;
        label(field[2], 20, y, 180, 24);
        local row = {};
        inputs[field[1]] = row;
        for column, x in ipairs({ 205, 300, 400 }) do
            local entry = Turbine.UI.Lotro.TextBox();
            entry:SetParent(win);
            entry:SetPosition(x, y);
            entry:SetSize(column == 3 and 180 or 75, 21);
            entry:SetMultiline(false);
            entry:SetFont(Turbine.UI.Lotro.Font.Verdana14);
            entry:SetForeColor(Turbine.UI.Color(1, 1, 1));
            entry:SetBackColor(Turbine.UI.Color(0.1, 0.12, 0.16));
            row[column] = entry;
            if (column == 3) then referenceInputs[#referenceInputs + 1] = entry; end
        end
        row[1]:SetText(tostring(config and config.weights and config.weights[field[1]]
            or defaults[field[1]] or 0));
        row[2]:SetText(tostring(roleDefaults[field[1]] or 0));
        row[3]:SetText(config and config.references and config.references[field[1]] and
            tostring(config.references[field[1]]) or "");
    end
    label("Final weight combines Class EV and Role value: (Class EV x 5 + Role value / 5) / 6.",
        20, 575, 710, 34);
    label("Finesse target % (blank = off):", 20, 614, 260, 24);
    local finesseTarget = Turbine.UI.Lotro.TextBox();
    finesseTarget:SetParent(win);
    finesseTarget:SetPosition(285, 614);
    finesseTarget:SetSize(85, 24);
    finesseTarget:SetMultiline(false);
    finesseTarget:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    finesseTarget:SetText(config and config.finesseTarget ~= nil and tostring(config.finesseTarget) or "");
    local resistReference = StatCapsTheme.Button();
    resistReference:SetParent(win);
    resistReference:SetPosition(380, 614);
    resistReference:SetSize(220, 24);
    resistReference:SetText(T("Use 35% resist reference"));
    resistReference.Click = function()
        finesseTarget:SetText("35");
        if (tonumber(inputs.Finesse[1]:GetText()) == 0) then inputs.Finesse[1]:SetText("1"); end
        if (tonumber(inputs.Finesse[2]:GetText()) == 0) then inputs.Finesse[2]:SetText("1"); end
    end;
    label("Physical: B/P/E. Tactical/DoTs/some tank threat skills: check resists.\n35% is a supplied high-difficulty reference, not a universal target.", 20, 643, 710, 40);
    local status = label(defaultError or (config and config.preset and
        ("Loaded " .. config.preset .. " EV weights (editable).") or ""), 20, 688, 710, 18);
    local confirmWin = StatCapsTheme.Window();
    confirmWin:SetText(T("Confirm scoring changes"));
    confirmWin:SetSize(500, 220);
    StatCapsTheme.Panel(confirmWin, 500, 220);
    confirmWin:SetPosition(math.max(0, (width - 500) / 2), math.max(0, (height - 220) / 2));
    local confirmText = Turbine.UI.Label();
    confirmText:SetParent(confirmWin);
    confirmText:SetPosition(24, 48);
    confirmText:SetSize(450, 90);
    confirmText:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    confirmText:SetForeColor(Turbine.UI.Color(0.95, 0.9, 0.75));
    confirmText:SetText(T("Are you sure you want to save these custom scoring values for " ..
        profile.name .. "?\nThey change StatCaps estimates and recommendations, not your character's stats.\n" ..
        "You can undo them later with Reset build defaults in the Scoring menu."));
    confirmWin:SetVisible(false);
    local pendingConfig;
    local confirm = StatCapsTheme.Button();
    confirm:SetParent(confirmWin);
    confirm:SetPosition(24, 160);
    confirm:SetSize(215, 28);
    confirm:SetText(T("Confirm and save"));
    confirm.Click = function()
        if (not pendingConfig) then return; end
        save(pendingConfig);
        pendingConfig = nil;
        confirmWin:SetVisible(false);
        win:SetVisible(false);
    end
    local cancel = StatCapsTheme.Button();
    cancel:SetParent(confirmWin);
    cancel:SetPosition(260, 160);
    cancel:SetSize(180, 28);
    cancel:SetText(T("Cancel"));
    cancel.Click = function()
        pendingConfig = nil;
        confirmWin:SetVisible(false);
    end
    for index, colour in ipairs({ "Blue", "Red", "Yellow" }) do
        local choice = colour;
        local presetButton = StatCapsTheme.Button();
        presetButton:SetParent(win);
        presetButton:SetPosition(175 + (index - 1) * 165, 170);
        presetButton:SetSize(130, 26);
        presetButton:SetText(T(colour .. " EV"));
        presetButton:SetEnabled(sheetPresets[profile.className] ~= nil
            and sheetPresets[profile.className][colour] ~= nil);
        presetButton.Click = function()
            local preset, err = StatCapsScoring.Preset(profile.className, choice, calc);
            if (not preset) then status:SetText(T(err)); return; end
            mode, metadata = preset.mode, preset;
            modes();
            for key, row in pairs(inputs) do
                row[1]:SetText(tostring(preset.weights[key]));
                row[3]:SetText(preset.references[key] and tostring(preset.references[key]) or "");
            end
            status:SetText(T("Editor replaced with " .. preset.preset ..
                " values; nothing saved yet. Click Save scoring to apply."));
        end;
    end
    local function button(text, x, w, click)
        local control = StatCapsTheme.Button();
        control:SetParent(win);
        control:SetPosition(x, 718);
        control:SetSize(w, 25);
        control:SetText(T(text));
        control.Click = click;
        return control;
    end
    loadAmountsButton = button("Load sheet amounts", 20, 195, function()
        for _, field in ipairs(StatCapsScoring.Fields) do
            if (field[1] ~= "Morale" or not (metadata and metadata.preset)) then
                inputs[field[1]][3]:SetText(field[3] and tostring(field[3]) or "");
            end
        end
        status:SetText(T("Loaded sheet amounts only; scoring weights unchanged."));
    end);
    button("Reset build defaults", 220, 185, function()
        pendingConfig = nil;
        confirmWin:SetVisible(false);
        save(nil);
        win:SetVisible(false);
    end);
    button("Save scoring", 410, 190, function()
        local weights, references, roleWeights = {}, {}, {};
        for key, row in pairs(inputs) do
            weights[key], roleWeights[key], references[key] = row[1]:GetText(), row[2]:GetText(), row[3]:GetText();
        end
        local settings = { finesseTarget = finesseTarget:GetText(),
            preset = metadata and metadata.preset, roleWeights = roleWeights };
        local validated, err = StatCapsScoring.Validate(mode, weights, references, settings);
        if (not validated) then status:SetText(T(err)); return; end
        if (validated.finesseTarget and validated.finesseTarget > 0
            and StatCapsScoring.EffectiveWeight(validated.weights.Finesse,
                validated.roleWeights.Finesse) == 0) then
            status:SetText(T("Set a positive Finesse class EV or role value to use this target."));
            return;
        end
        pendingConfig = validated;
        confirmWin:SetVisible(true);
        confirmWin:Activate();
    end);
    win:SetVisible(true);
    win:Activate();
    modes();
    return win;
end
