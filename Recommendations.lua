StatCapsAdvice = {};

local classes = {
    Beorning = { damage = "PhysicalMastery", roles = { "DD", "Tank", "Heal" } },
    Brawler = { damage = "PhysicalMastery", roles = { "DD", "Tank" } },
    Burglar = { damage = "PhysicalMastery", roles = { "DD", "Support" } },
    Captain = { damage = "PhysicalMastery", roles = { "DD", "Tank", "Heal", "Support" } },
    Champion = { damage = "PhysicalMastery", roles = { "DD", "Tank" } },
    Guardian = { damage = "PhysicalMastery", roles = { "DD", "Tank" } },
    Hunter = { damage = "PhysicalMastery", roles = { "DD" } },
    LoreMaster = { damage = "TacticalMastery", roles = { "DD", "Support" } },
    Mariner = { damage = "PhysicalMastery", roles = { "DD", "Support" } },
    Minstrel = { damage = "TacticalMastery", roles = { "DD", "Heal" } },
    RuneKeeper = { damage = "TacticalMastery", roles = { "DD", "Heal" } },
    Warden = { damage = "PhysicalMastery", roles = { "DD", "Tank" } }
};

function StatCapsAdvice.Roles(className)
    return classes[className] and classes[className].roles or {};
end

function StatCapsAdvice.Profile(className, role)
    local class = classes[className];
    if (not class) then return nil; end
    local supported = false;
    for _, choice in ipairs(class.roles) do
        if (role == choice) then supported = true; end
    end
    if (not supported) then return nil; end

    local profile = { name = role .. " " .. className, className = className, role = role, damage = class.damage };
    if (role == "Tank") then
        profile.primary = { "PhysicalMitigation", "TacticalMitigation" };
        profile.note = "Tank: mitigations and morale first. Incoming healing and resistance take priority over critical defence; balance usable avoidance and damage.";
    elseif (role == "Heal") then
        -- Use healing output directly; a damage-mastery cap is not a healing target.
        profile.primary = { "CritHit", "OutHeal" };
        profile.note = "Healer: critical rating and outgoing healing first, then survival. Damage has a small comparison weight, but its mastery cap is not a healing goal.";
    elseif (role == "Support") then
        profile.primary = { "PhysicalMitigation", "TacticalMitigation" };
        profile.note = "Support: reliable debuffs and staying alive come first. Balance critical rating and " ..
            (class.damage == "PhysicalMastery" and "physical" or "tactical") ..
            " mastery for damage; neither is a universal support requirement.";
    else
        profile.primary = { "CritHit", class.damage };
        profile.note = "DD: critical rating and " ..
            (class.damage == "PhysicalMastery" and "physical" or "tactical") ..
            " mastery for damage. Keep enough survivability for the fight.";
    end
    profile.situational = "Finesse: adjust for misses/resists, not its cap. Resistance and avoidance depend on the encounter.";
    profile.nextStats = {};
    for _, key in ipairs(profile.primary) do
        profile.nextStats[#profile.nextStats + 1] = { key = key };
    end
    if (role ~= "Tank" and role ~= "Support") then
        profile.nextStats[#profile.nextStats + 1] = { key = "PhysicalMitigation" };
        profile.nextStats[#profile.nextStats + 1] = { key = "TacticalMitigation" };
    end
    if (role == "Support") then
        profile.nextStats[#profile.nextStats + 1] = { key = "CritHit", situational = true };
        profile.nextStats[#profile.nextStats + 1] = { key = class.damage, situational = true };
    end
    if (role == "Tank") then
        profile.nextStats[#profile.nextStats + 1] = { key = "InHeal", situational = true };
        profile.nextStats[#profile.nextStats + 1] = { key = "Resist", situational = true };
        profile.nextStats[#profile.nextStats + 1] = { key = "CritDef", situational = true };
    end
    profile.nextStats[#profile.nextStats + 1] = {
        key = "Finesse", situational = true,
        reason = "Only add finesse if attacks or debuffs miss/resist. Its cap is not a gearing goal."
    };
    if (role == "Tank") then
        for _, key in ipairs({ "Block", "Parry", "Evade" }) do
            profile.nextStats[#profile.nextStats + 1] = { key = key, situational = true };
        end
    else
        profile.nextStats[#profile.nextStats + 1] = { key = "CritDef", situational = true };
    end
    if (role ~= "Tank") then
        profile.nextStats[#profile.nextStats + 1] = { key = "Resist", situational = true };
    end
    if (class.damage == "PhysicalMastery" and role ~= "Heal") then
        profile.ignore = "Tactical Mastery is not a damage-gearing priority for this build.";
    elseif (class.damage == "TacticalMastery") then
        profile.ignore = "Physical Mastery is not a gearing priority for this build.";
    else
        profile.ignore = "Use Outgoing Healing to judge healing output. Physical Mastery has a small damage weight, not a healing-cap target.";
    end
    return profile;
end

function StatCapsAdvice.Next(profile, samples, skipped)
    local result = { completed = 0, skipped = 0, unavailable = 0 };
    if (not profile) then return result; end
    local goals = profile.nextStats;
    if (profile.scoringPriorities) then
        goals = {};
        for index, goal in ipairs(profile.nextStats) do
            local sample = samples[goal.key];
            local reference, factor = StatCapsScoring.Reference(profile, goal.key,
                sample and (sample.hardLimit or sample.limit));
            local value = 0;
            if (sample and sample.valid and reference and reference > 0) then
                value = math.min(reference, math.max(0, sample.limit - sample.rating))
                    / reference * factor * goal.weight;
            end
            goals[#goals + 1] = { key = goal.key, weight = goal.weight, value = value,
                situational = goal.situational, reason = goal.reason, order = index };
        end
        table.sort(goals, function(a, b)
            if (a.value == b.value) then return a.order < b.order; end
            return a.value > b.value;
        end);
    end
    for _, goal in ipairs(goals) do
        local sample = samples[goal.key];
        if (not sample or not sample.valid) then
            -- Unsupported avoidance is absent from samples; do not recommend it.
            if (sample) then result.unavailable = result.unavailable + 1; end
        elseif (sample.rating >= sample.limit - 0.5) then
            result.completed = result.completed + 1;
        elseif (skipped[goal.key]) then
            result.skipped = result.skipped + 1;
        elseif (not result.goal) then
            result.goal = {
                key = goal.key, label = sample.label, amount = sample.limit - sample.rating,
                situational = goal.situational, reason = goal.reason
            };
        end
    end
    return result;
end

function StatCapsAdvice.ScoringPriorities(profile)
    local weights = StatCapsAdvice.Weights(profile);
    local goals = {};
    for _, field in ipairs(StatCapsScoring.Fields) do
        local key = field[1];
        if (key ~= "Morale" and key ~= "Fate" and key ~= "Vitality" and key ~= "Armour"
            and weights[key] and weights[key] > 0) then
            local situational = key == "Finesse" or key == "Block" or key == "Parry"
                or key == "Evade" or key == "Resist" or key == "CritDef" or key == "InHeal";
            goals[#goals + 1] = { key = key, weight = weights[key], situational = situational,
                reason = "Ranked by the benefit of gaining one essence's worth of each stat at your current ratings. "
                    .. (situational and "Encounter-dependent; this cap is not a gearing target."
                        or "Compare complete items and encounter needs; this is not a requirement to cap the stat.") };
        end
    end
    table.sort(goals, function(a, b)
        if (a.weight == b.weight) then return a.key < b.key; end
        return a.weight > b.weight;
    end);
    profile.nextStats, profile.primary, profile.scoringPriorities = goals, {}, true;
    for _, goal in ipairs(goals) do profile.primary[#profile.primary + 1] = goal.key; end
    profile.note = StatCapsScoring.Description(profile);
    profile.ignore = "Stats with zero combined weight are excluded from priorities and scoring. Above-cap gains have no value.";
    profile.situational = "Fate and Vitality use direct EV weights; the supplied table leaves Morale blank. "
        .. "Finesse and avoidance remain encounter-dependent, even when their EV weight is high.";
end

function StatCapsAdvice.Evaluate(profile, samples)
    local result = { gaps = {}, surplus = {}, unavailable = {} };
    if (not profile) then return result; end
    for index, key in ipairs(profile.primary) do
        local sample = samples[key];
        if (not sample or not sample.valid) then
            result.unavailable[#result.unavailable + 1] = key;
        else
            local difference = sample.limit - sample.rating;
            local item = {
                key = key, label = sample.label, amount = math.abs(difference),
                ratio = sample.rating / sample.limit, order = index
            };
            if (difference >= 0.5) then
                result.gaps[#result.gaps + 1] = item;
            elseif (difference <= -0.5) then
                result.surplus[#result.surplus + 1] = item;
            end

        end
    end
    -- Only compare shortfalls within this build's relevant priorities.
    table.sort(result.gaps, function(a, b)
        if (a.ratio == b.ratio) then return a.order < b.order; end
        return a.ratio < b.ratio;
    end);
    return result;
end

function StatCapsAdvice.Weights(profile)
    if (profile.scoring) then
        local weights = {};
        for key, weight in pairs(profile.scoring.weights) do
            local roleValue = profile.scoring.roleWeights and profile.scoring.roleWeights[key] or 0;
            local effectiveWeight = StatCapsScoring.EffectiveWeight(weight, roleValue);
            if (effectiveWeight > 0) then weights[key] = effectiveWeight; end
        end
        if (not profile.scoring.finesseTarget or profile.scoring.finesseTarget == 0) then weights.Finesse = nil; end
        return weights;
    end
    local weights = {
        PhysicalMitigation = 2, TacticalMitigation = 2, Morale = 1,
        CritDef = 0.5, Finesse = 0.5, Resist = 0.25, CritHit = 0.5
    };
    weights[profile.damage] = 0.5;
    for _, key in ipairs(profile.primary) do weights[key] = 5; end
    if (profile.role == "Tank") then
        weights.Morale, weights.InHeal, weights.Resist, weights.CritDef = 5, 2, 2, 1;
        weights.Block, weights.Parry, weights.Evade = 1, 1, 1;
    elseif (profile.role == "Heal") then
        weights.PhysicalMitigation, weights.TacticalMitigation, weights.Morale = 3, 3, 2;
    elseif (profile.role == "Support") then
        weights.Morale, weights.CritHit, weights.Finesse = 3, 2, 1;
        weights[profile.damage] = 1;
    end
    return weights;
end

local attributeNames = { "Might", "Agility", "Vitality", "Will", "Fate" };
local bonuses = {
    { "PhyMas", "phys mastery" }, { "TacMas", "tact mastery" },
    { "OutHeal", "outgoing healing" }, { "CritHit", "crit" },
    { "PhyMit", "phys mit" }, { "TacMit", "tact mit" },
    { "Block", "block" }, { "Parry", "parry" }, { "Evade", "evade" },
    { "Finesse", "finesse" }, { "Resist", "resistance" },
    { "Morale", "morale" }, { "Power", "power" },
    { "ICMR", "in-combat morale regen" }, { "NCMR", "out-of-combat morale regen" },
    { "ICPR", "in-combat power regen" }, { "NCPR", "out-of-combat power regen" }
};
local primaryBonus = {
    PhysicalMastery = "PhyMas", TacticalMastery = "TacMas", CritHit = "CritHit",
    OutHeal = "OutHeal", PhysicalMitigation = "PhyMit", TacticalMitigation = "TacMit"
};

function StatCapsAdvice.Attributes(calc, className, values)
    local result = {};
    if (not classes[className]) then return result; end
    for _, attribute in ipairs(attributeNames) do
        local item = { name = attribute, value = values[attribute], bonuses = {}, text = {} };
        for _, bonus in ipairs(bonuses) do
            local amount = calc(className .. "CD" .. attribute .. "To" .. bonus[1], 1);
            -- Tactical mastery also contributes to outgoing healing for some classes.
            if (bonus[1] == "OutHeal") then
                amount = amount + calc(className .. "CD" .. attribute .. "ToTacMas", 1)
                    * calc(className .. "CDTacMasToOutHeal", 1);
            end
            assert(type(amount) == "number" and amount >= 0,
                "Invalid attribute conversion for " .. className .. " / " .. attribute);
            item.bonuses[bonus[1]] = amount;
            if (amount > 0) then
                item.text[#item.text + 1] = "+" .. tostring(amount) .. " " .. bonus[2];
            end
        end
        result[#result + 1] = item;
    end
    return result;
end

function StatCapsAdvice.AttributeHint(result, attributes)
    for _, gap in ipairs(result.gaps) do
        local bonus = primaryBonus[gap.key];
        if (bonus) then
            local best;
            for _, item in ipairs(attributes) do
                if (item.value and item.bonuses[bonus] > 0
                    and (not best or item.bonuses[bonus] > best.bonuses[bonus])) then
                    best = item;
                end
            end
            if (best) then
                return "For " .. gap.label .. ", " .. best.name .. " gives the largest base gain per point (+" ..
                    tostring(best.bonuses[bonus]) .. "). Compare total item stats, not just attributes.";
            end
        end
    end
    return "No attribute increase is implied by these cap values. Compare useful rating gains and survivability.";
end
