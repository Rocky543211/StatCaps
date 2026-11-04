StatCapsVirtues = {};

function StatCapsVirtues.Limits(level)
    if (type(level) ~= "number" or level % 1 ~= 0 or not StatCapsVirtueData.caps[level]) then
        return nil, "Virtue data supports character levels 1-160 only.";
    end
    local slots = 0;
    for _, unlock in ipairs({ 7, 9, 11, 17, 23 }) do
        if (level >= unlock) then slots = slots + 1; end
    end
    return { rank = StatCapsVirtueData.caps[level], slots = slots };
end

function StatCapsVirtues.Find(name)
    for _, virtue in ipairs(StatCapsVirtueData.virtues) do
        if (virtue.name == name) then return virtue; end
    end
end

function StatCapsVirtues.ValidateRanks(ranks)
    if (type(ranks) ~= "table") then return nil, "Enter and save all 21 virtue ranks first."; end
    local normalized = {};
    for _, virtue in ipairs(StatCapsVirtueData.virtues) do
        local rank = tonumber(ranks[virtue.name]);
        if (not rank or rank % 1 ~= 0 or rank < 0 or rank > 100) then
            return nil, virtue.name .. ": enter a whole earned rank from 0 to 100 (0 = untrained).";
        end
        normalized[virtue.name] = rank;
    end
    return normalized;
end

function StatCapsVirtues.ParseImport(text)
    if (type(text) ~= "string" or #text > 8192) then return nil, "Invalid virtue import. Paste the helper's complete output."; end
    local lines = {};
    for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line; end
    if (lines[1] ~= "STATCAPS-VIRTUES-1" or not lines[2] or not lines[2]:match("^Character: .+")) then
        return nil, "Invalid virtue import. Paste the helper's complete output.";
    end
    local character = lines[2]:sub(12);
    local ranks = {};
    for i = 3, #lines do
        if (lines[i] ~= "") then
            local name, rank = lines[i]:match("^([A-Za-z]+)=(%d+)$");
            if (not name or not StatCapsVirtues.Find(name) or ranks[name] ~= nil) then
                return nil, "Invalid or duplicate virtue in imported data.";
            end
            ranks[name] = tonumber(rank);
        end
    end
    local normalized, err = StatCapsVirtues.ValidateRanks(ranks);
    if (not normalized) then return nil, err; end
    return normalized, character;
end

-- Deliberately accept complete rank notifications, not XP awards or player chat.
function StatCapsVirtues.ParseRankMessage(message)
    if (type(message) ~= "string") then return; end
    local text = string.lower(message:gsub("<[^>]->", ""):gsub("^%s+", ""):gsub("%s+$", ""));
    local patterns = {
        "^your (.-) virtue trait has changed to level (%d+)[%.!]?$",
        "^your (.-) virtue has advanced to rank (%d+)[%.!]?$",
        "^your virtue (.-) has advanced to rank (%d+)[%.!]?$",
        "^your (.-) virtue has increased to rank (%d+)[%.!]?$",
        "^(.-) virtue has advanced to rank (%d+)[%.!]?$",
        "^(.-) has reached rank (%d+)[%.!]?$",
        "^your (.-) virtue is now rank (%d+)[%.!]?$"
    };
    for _, pattern in ipairs(patterns) do
        local name, rank = text:match(pattern);
        if (name) then
            for _, virtue in ipairs(StatCapsVirtueData.virtues) do
                if (string.lower(virtue.name) == name) then
                    rank = tonumber(rank);
                    if (rank >= 1 and rank <= 100) then return virtue.name, rank; end
                end
            end
        end
    end
end

function StatCapsVirtues.UpdateRank(ranks, name, rank)
    if (not StatCapsVirtues.Find(name) or type(rank) ~= "number" or
        rank % 1 ~= 0 or rank < 1 or rank > 100) then return false; end
    local previous = tonumber(ranks[name]);
    if (previous and previous >= rank) then return false; end
    ranks[name] = rank;
    return true;
end

function StatCapsVirtues.Validate(level, selection)
    if (type(selection) ~= "table") then return nil, "Enter your equipped virtues, or choose None."; end
    local limits, err = StatCapsVirtues.Limits(level);
    if (not limits) then return nil, err; end
    local seen, normalized = {}, {};
    for index = 1, 5 do
        local choice = selection[index];
        if (choice and type(choice) ~= "table") then return nil, "Invalid virtue in slot " .. index .. "."; end
        if (choice and choice.name) then
            if (index > limits.slots) then return nil, "Slot " .. index .. " is locked at this level."; end
            if (not StatCapsVirtues.Find(choice.name)) then return nil, "Unknown virtue in slot " .. index .. "."; end
            if (seen[choice.name]) then return nil, "A virtue cannot occupy two slots: " .. choice.name .. "."; end
            local rank = tonumber(choice.rank);
            if (not rank or rank % 1 ~= 0 or rank < 1 or rank > limits.rank) then
                return nil, "Slot " .. index .. ": enter a whole rank from 1 to " .. limits.rank .. ".";
            end
            seen[choice.name] = true;
            normalized[index] = { name = choice.name, rank = rank };
        end
    end
    return normalized;
end

local function addBonuses(target, values)
    for key, value in pairs(values) do target[key] = (target[key] or 0) + value; end
end

function StatCapsVirtues.Recommend(calc, className, profile, snapshot, level, selection, earnedRanks)
    local ranks;
    if (earnedRanks ~= nil) then
        local err;
        ranks, err = StatCapsVirtues.ValidateRanks(earnedRanks);
        if (not ranks) then return nil, err; end
        local limits, limitError = StatCapsVirtues.Limits(level);
        if (not limits) then return nil, limitError; end
        if (type(selection) ~= "table") then return nil, "Choose your equipped virtues, or None."; end
        local effective = {};
        for index, choice in pairs(selection) do
            if (type(choice) ~= "table") then return nil, "Invalid virtue in slot " .. tostring(index) .. "."; end
            effective[index] = { name = choice.name, rank = ranks[choice.name] and
                math.min(ranks[choice.name], limits.rank) or choice.rank };
            if (ranks[choice.name] == 0) then
                return nil, choice.name .. " is untrained. Correct its saved rank or choose None.";
            end
        end
        selection = effective;
    end
    local normalized, err = StatCapsVirtues.Validate(level, selection);
    if (not normalized) then return nil, err; end
    local limits = StatCapsVirtues.Limits(level);
    local _, _, scoreError = StatCapsComparison.Score(profile, snapshot, snapshot);
    if (scoreError) then return nil, scoreError; end
    for _, key in ipairs({ "Might", "Agility", "Vitality", "Will", "Fate" }) do
        if (type(snapshot.attributes[key]) ~= "number") then
            return nil, "Cannot project virtues: missing " .. key .. ".";
        end
    end
    local zero, equipped = StatCapsManual.Parse({}), StatCapsManual.Parse({});
    for _, choice in pairs(normalized) do
        addBonuses(equipped, StatCapsVirtues.Find(choice.name).ranks[choice.rank]);
    end
    local empty = StatCapsComparison.Capture(snapshot.samples, snapshot.attributes, 0, 0);
    empty.level = snapshot.level;
    for _, sample in pairs(empty.samples) do sample.rating = 0; end
    for key in pairs(empty.attributes) do empty.attributes[key] = 0; end
    local removed = StatCapsManual.Project(calc, className, empty, zero, equipped);
    for key, sample in pairs(snapshot.samples) do
        if (sample.valid and removed.samples[key].rating > sample.rating + 0.01) then
            return nil, "Entered virtues exceed current " .. sample.label .. ". Check equipped choices/ranks and buffs.";
        end
    end
    if (removed.morale >= snapshot.morale) then
        return nil, "Entered virtues exceed current maximum morale. Check choices/ranks.";
    end
    for key, value in pairs(snapshot.attributes) do
        if (removed.attributes[key] > value + 0.01) then
            return nil, "Entered virtues exceed current " .. key .. ". Check choices/ranks.";
        end
    end
    local base = StatCapsManual.Project(calc, className, snapshot, equipped, zero);
    local baseAttributes, attributeError = StatCapsComparison.AttributeRatingChanges(profile, snapshot, base);
    if (not baseAttributes) then return nil, attributeError; end
    local equippedNames = {};
    for _, choice in pairs(normalized) do equippedNames[choice.name] = choice.rank; end
    local candidates = {};
    for _, virtue in ipairs(StatCapsVirtueData.virtues) do
        local rank = ranks and math.min(ranks[virtue.name], limits.rank) or limits.rank;
        if (rank > 0) then
            local values = StatCapsManual.Parse({});
            addBonuses(values, virtue.ranks[rank]);
            local contribution = StatCapsManual.Project(calc, className, empty, zero, values);
            local attributes, err = StatCapsComparison.AttributeRatingChanges(profile, empty, contribution);
            if (not attributes) then return nil, err; end
            candidates[#candidates + 1] = {
                name = virtue.name, rank = rank, values = values,
                contribution = contribution, attributeChanges = attributes,
                equipped = equippedNames[virtue.name] == rank
            };
        end
    end
    -- Compare every legal set. Sum derived contributions before clipping at caps.
    local dimensions, totals = {}, {};
    local references = {};
    for _, field in ipairs(StatCapsScoring.Fields) do references[field[1]] = field[3]; end
    for key, weight in pairs(StatCapsAdvice.Weights(profile)) do
        if (key == "Fate" or key == "Vitality" or key == "Armour" or key == "Morale") then
            local value, reference;
            if (key == "Fate" or key == "Vitality") then
                value, reference = base.attributes[key], references[key];
            elseif (key == "Armour") then value, reference = base.armour, snapshot.armour;
            else value, reference = base.morale - (baseAttributes.Morale or 0), snapshot.morale; end
            dimensions[#dimensions + 1] = { key = key, base = value, cap = math.huge,
                reference = reference, weight = weight };
        elseif (base.samples[key]) then
            local sample = base.samples[key];
            local cap, err = StatCapsScoring.Limit(profile, key, sample, snapshot.level);
            if (not cap) then return nil, err; end
            dimensions[#dimensions + 1] = { key = key, base = sample.rating - (baseAttributes[key] or 0),
                cap = cap, reference = sample.limit, weight = weight };
        end
    end
    for _, dimension in ipairs(dimensions) do
        if (profile.scoring) then
            local reference, factor = StatCapsScoring.Reference(profile, dimension.key, dimension.reference);
            dimension.reference = reference;
            dimension.weight = dimension.weight * factor;
        else
            dimension.weight = dimension.weight * 100;
        end
    end
    for d, dimension in ipairs(dimensions) do
        totals[d] = dimension.base;
        for _, candidate in ipairs(candidates) do
            local key = dimension.key;
            if (key == "Fate" or key == "Vitality") then candidate[d] = candidate.contribution.attributes[key];
            elseif (key == "Armour") then candidate[d] = candidate.contribution.armour;
            elseif (key == "Morale") then
                candidate[d] = candidate.contribution.morale - (candidate.attributeChanges.Morale or 0);
            else
                candidate[d] = candidate.contribution.samples[key].rating - (candidate.attributeChanges[key] or 0);
            end
        end
    end
    local bestScore, bestKept, best, chosen = -math.huge, -1, {}, {};
    local function search(start, remaining)
        if (remaining == 0) then
            local score, kept = 0, 0;
            for d, dimension in ipairs(dimensions) do
                score = score + math.min(math.max(0, totals[d]), dimension.cap) / dimension.reference * dimension.weight;
            end
            for _, candidate in ipairs(chosen) do if (candidate.equipped) then kept = kept + 1; end end
            if (score > bestScore + StatCapsScoring.ScoreTolerance
                or (math.abs(score - bestScore) <= StatCapsScoring.ScoreTolerance and kept > bestKept)) then
                bestScore, bestKept, best = score, kept, {};
                for i, candidate in ipairs(chosen) do best[i] = candidate; end
            end
            return;
        end
        for i = start, #candidates - remaining + 1 do
            local candidate = candidates[i];
            chosen[#chosen + 1] = candidate;
            for d in ipairs(dimensions) do totals[d] = totals[d] + candidate[d]; end
            search(i + 1, remaining - 1);
            for d in ipairs(dimensions) do totals[d] = totals[d] - candidate[d]; end
            chosen[#chosen] = nil;
        end
    end
    search(1, math.min(limits.slots, #candidates));
    local bonuses = StatCapsManual.Parse({});
    for _, candidate in ipairs(best) do addBonuses(bonuses, candidate.values); end
    local projected = StatCapsManual.Project(calc, className, base, zero, bonuses);
    local score, details, finalError = StatCapsComparison.Score(profile, snapshot, projected);
    if (not score) then return nil, finalError; end
    return { choices = best, score = score, details = details, limits = limits,
        selection = normalized, actualRanks = ranks ~= nil, projected = projected };
end
