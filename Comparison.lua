StatCapsComparison = {};

function StatCapsComparison.Capture(samples, attributes, morale, armour)
    local snapshot = { samples = {}, attributes = {}, morale = morale, armour = armour };
    for key, sample in pairs(samples) do
        snapshot.samples[key] = {
            label = sample.label, rating = sample.rating, limit = sample.limit, valid = sample.valid
        };
    end
    for key, value in pairs(attributes) do snapshot.attributes[key] = value; end
    return snapshot;
end

local attributeRatingConversions = {
    PhysicalMastery = "PhyMas", TacticalMastery = "TacMas", CritHit = "CritHit",
    Finesse = "Finesse", OutHeal = "OutHeal", PhysicalMitigation = "PhyMit",
    TacticalMitigation = "TacMit", Block = "Block", Parry = "Parry", Evade = "Evade",
    Resist = "Resist", CritDef = "CritDef", InHeal = "InHeal", Morale = "Morale"
};

function StatCapsComparison.AttributeRatingChanges(profile, before, after)
    local weights = StatCapsAdvice.Weights(profile);
    if (not weights.Fate and not weights.Vitality) then return {}; end
    if (type(CalcStat) ~= "function") then return nil, "Score unavailable: CalcStat is needed to avoid double-counting attributes."; end
    local attributeDeltas = {};
    for _, key in ipairs({ "Fate", "Vitality" }) do
        if (weights[key]) then
            local old, new = before.attributes[key], after.attributes[key];
            if (old == nil or new == nil) then return nil, "Score unavailable: missing " .. key .. "."; end
            attributeDeltas[key] = new - old;
        end
    end
    local cache = {};
    local function conversion(attribute, suffix)
        local name = profile.className .. "CD" .. attribute .. "To" .. suffix;
        if (cache[name] == nil) then
            local value = CalcStat(name, 1);
            if (type(value) ~= "number" or value ~= value) then
                return nil, "Score unavailable: invalid attribute conversion " .. name .. ".";
            end
            cache[name] = value;
        end
        return cache[name];
    end
    local result = {};
    for key, suffix in pairs(attributeRatingConversions) do
        local value = 0;
        for attribute, delta in pairs(attributeDeltas) do
            local amount, err = conversion(attribute, suffix);
            if (amount == nil) then return nil, err; end
            value = value + delta * amount;
        end
        if (key == "OutHeal") then
            for attribute, delta in pairs(attributeDeltas) do
                local mastery, err = conversion(attribute, "TacMas");
                if (mastery == nil) then return nil, err; end
                value = value + delta * mastery * CalcStat(profile.className .. "CDTacMasToOutHeal", 1);
            end
        elseif (key == "PhysicalMitigation") then
            value = value * CalcStat(profile.className .. "CDPhyMitToComPhyMit", 1);
        end
        result[key] = value;
    end
    return result;
end

function StatCapsComparison.Score(profile, before, after)
    if (profile.scoringError) then return nil, {}, profile.scoringError; end
    local total, details, missing = 0, {}, {};
    local weights = StatCapsAdvice.Weights(profile);
    local attributeChanges, attributeError = StatCapsComparison.AttributeRatingChanges(profile, before, after);
    if (not attributeChanges) then return nil, details, attributeError; end
    local defaultReferences = {};
    for _, field in ipairs(StatCapsScoring.Fields) do defaultReferences[field[1]] = field[3]; end
    for key, weight in pairs(weights) do
        local old, new = before.samples[key], after.samples[key];
        local reference, useful, delta, label;
        if (key == "Fate" or key == "Vitality") then
            local oldValue, newValue = before.attributes[key], after.attributes[key];
            if (oldValue ~= nil and newValue ~= nil) then
                reference, useful, delta, label = defaultReferences[key], newValue - oldValue,
                    newValue - oldValue, key;
            else
                missing[#missing + 1] = key;
            end
        elseif (key == "Armour") then
            if (before.armour and after.armour) then
                reference, useful, delta, label = before.armour, after.armour - before.armour,
                    after.armour - before.armour, "Armour";
            else
                missing[#missing + 1] = "Armour";
            end
        elseif (key == "Morale") then
            if (before.morale and before.morale > 0 and after.morale) then
                delta = after.morale - before.morale - (attributeChanges.Morale or 0);
                useful = after.morale - (attributeChanges.Morale or 0) - before.morale;
                reference, label = before.morale, "Max Morale";
            else
                missing[#missing + 1] = "Max Morale";
            end
        elseif (old and new and old.valid and new.valid and old.limit > 0 and new.limit == old.limit) then
            reference = old.limit;
            local limit, err = StatCapsScoring.Limit(profile, key, old, before.level);
            if (not limit) then return nil, details, err; end
            delta = new.rating - old.rating - (attributeChanges[key] or 0);
            useful = math.min(math.max(0, new.rating - (attributeChanges[key] or 0)), limit)
                - math.min(math.max(0, old.rating), limit);
            label = old.label;
        elseif (old or new) then
            missing[#missing + 1] = (old or new).label;
        elseif (key ~= "Block" and key ~= "Parry" and key ~= "Evade") then
            missing[#missing + 1] = key;
        end
        if (reference) then
            local factor = 100;
            if (profile.scoring) then
                reference, factor = StatCapsScoring.Reference(profile, key, reference);
            end
            if (not reference or reference <= 0) then return nil, details, "Score unavailable: missing reference for " .. key; end
            local points = factor * useful / reference * weight;
            total = total + points;
            if (math.abs(delta or 0) >= 0.01) then
                details[#details + 1] = {
                    key = key, label = label, delta = delta or 0, useful = useful,
                    points = points, weight = weight, reference = reference,
                    classWeight = profile.scoring and profile.scoring.weights[key],
                    roleWeight = profile.scoring and profile.scoring.roleWeights
                        and profile.scoring.roleWeights[key]
                };
            end
        end
    end
    table.sort(details, function(a, b)
        if (math.abs(a.points) == math.abs(b.points)) then return a.label < b.label; end
        return math.abs(a.points) > math.abs(b.points);
    end);
    table.sort(missing);
    return #missing == 0 and total or nil, details,
        #missing > 0 and ("Score unavailable: missing " .. table.concat(missing, ", ")) or nil;
end

function StatCapsComparison.Evaluate(profile, before, after)
    local result = { gains = {}, losses = {}, other = {}, attributes = {}, missing = {}, changed = false };
    local relevant = {};
    for _, goal in ipairs(profile.nextStats) do relevant[goal.key] = goal; end
    for key, old in pairs(before.samples) do
        local new = after.samples[key];
        if (not old.valid or not new or not new.valid) then
            result.missing[#result.missing + 1] = old.label;
        else
            local delta = new.rating - old.rating;
            if (math.abs(delta) >= 0.5) then
                result.changed = true;
                local limit, limitError = StatCapsScoring.Limit(profile, key, old, before.level);
                if (not limit) then result.missing[#result.missing + 1] = limitError; end
                local useful = limit and (math.min(math.max(new.rating, 0), limit)
                    - math.min(math.max(old.rating, 0), limit)) or 0;
                local goal = relevant[key];
                local item = {
                    label = old.label, delta = delta, useful = useful,
                    situational = goal and goal.situational
                };
                if (goal and useful >= 0.5) then
                    result.gains[#result.gains + 1] = item;
                elseif (goal and useful <= -0.5) then
                    result.losses[#result.losses + 1] = item;
                else
                    result.other[#result.other + 1] = item;
                end
            end
        end
    end
    for key, new in pairs(after.samples) do
        if (not before.samples[key]) then result.missing[#result.missing + 1] = new.label; end
    end
    for _, key in ipairs({ "Might", "Agility", "Vitality", "Will", "Fate" }) do
        local old, new = before.attributes[key], after.attributes[key];
        if (old and new) then
            if (math.abs(new - old) >= 0.5) then
                result.changed = true;
                result.attributes[#result.attributes + 1] = { label = key, delta = new - old };
            end
        else
            result.missing[#result.missing + 1] = key;
        end
    end
    if (before.morale and after.morale) then
        local delta = after.morale - before.morale;
        if (math.abs(delta) >= 0.5) then
            result.changed = true;
            local item = { label = "Max Morale", delta = delta, useful = delta, situational = true };
            local list = delta > 0 and result.gains or result.losses;
            list[#list + 1] = item;
        end
    else
        result.missing[#result.missing + 1] = "Max Morale";
    end
    local function sortItems(items)
        table.sort(items, function(a, b) return a.label < b.label; end);
    end
    sortItems(result.gains);
    sortItems(result.losses);
    sortItems(result.other);
    table.sort(result.missing);
    if (#result.missing > 0) then
        result.verdict = "Incomplete comparison: some stats are unavailable.";
    elseif (not result.changed) then
        result.verdict = "No measured changes yet. Equip the item yourself, then wait for refresh.";
    elseif (#result.gains > 0 and #result.losses > 0) then
        result.verdict = "Trade-off: useful gains and losses. No universal better/worse verdict.";
    elseif (#result.gains > 0) then
        result.verdict = "Improvement in measured useful stats; no measured useful losses.";
    elseif (#result.losses > 0) then
        result.verdict = "Downgrade in measured useful stats; no measured useful gains.";
    else
        result.verdict = "No useful rating gain detected for this build and tier.";
    end
    result.score, result.scoreDetails, result.scoreError = StatCapsComparison.Score(profile, before, after);
    return result;
end
