StatCapsBestGear = {};

local function copy(value)
    if (type(value) ~= "table") then return value; end
    local result = {};
    for key, entry in pairs(value) do result[key] = copy(entry); end
    return result;
end

local function add(target, values, factor)
    for _, field in ipairs(StatCapsManual.Fields) do
        local key = field[1];
        if (key ~= "WeaponDPS") then target[key] = (target[key] or 0) + (values[key] or 0) * (factor or 1); end
    end
end

local function bonuses(values)
    local text = {};
    for key, value in pairs(values or {}) do text[key] = tostring(value); end
    return StatCapsManual.Parse(text);
end

function StatCapsBestGear.InputKey(context, state)
    local function encode(value)
        if (type(value) ~= "table") then
            local text = tostring(value);
            return type(value) .. ":" .. #text .. ":" .. text;
        end
        local keys, parts = {}, {};
        for key in pairs(value) do keys[#keys + 1] = key; end
        table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b); end);
        for _, key in ipairs(keys) do parts[#parts + 1] = encode(key) .. encode(value[key]); end
        return "{" .. table.concat(parts) .. "}";
    end
    return encode({ context.level, context.className, context.characterName, context.snapshot,
        context.profile, context.equippedVirtues, state.original, state.extraOld, state.manualSetTotals, state.manualSets });
end

local function equippedVirtues(level, selection)
    local normalized, err = StatCapsVirtues.Validate(level, selection);
    if (not normalized) then return nil, err; end
    local total = StatCapsManual.Parse({});
    for _, choice in pairs(normalized) do add(total, StatCapsVirtues.Find(choice.name).ranks[choice.rank]); end
    return total;
end

function StatCapsBestGear.Eligible(record, rule, slot, context, options, original)
    if (record[9] or not StatCapsLoadouts.SlotFits(slot[3], record[6])) then return false; end
    if (not rule) then return false; end
    local requirements = record[8] or {};
    if (requirements.className and not StatCapsLoadouts.AllowsClass(requirements.className, context.className)) then return false; end
    if ((rule[1] > 0 and rule[1] > context.level) or (rule[2] > 0 and rule[2] < context.level)) then return false; end
    if (not options.unverified and (rule[1] == 0 or rule[6] ~= "")) then return false; end
    if (rule[3] > 0 and rule[3] <= 3 and slot[3] ~= "BACK" and rule[3] > context.armourType) then return false; end
    if (slot[3] == "MAIN_HAND" or slot[3] == "OFF_HAND" or slot[3] == "RANGED_ITEM" or slot[3] == "CLASS") then
        if (not options.weapons or not original or not original.id) then return false; end
        local worn = StatCapsGearRules[original.id];
        if (not worn or rule[3] ~= worn[3] or rule[4] ~= worn[4] or rule[5] ~= worn[5]) then return false; end
        if ((requirements.precludedSlot or "") ~= ((original.restrictions or {}).precludedSlot or "")) then return false; end
        if (slot[3] ~= "CLASS" and rule[3] < 4 and (not original.values or not original.values.WeaponDPS)) then return false; end
    end
    return true;
end

function StatCapsBestGear.GeneratedLevel(rule, characterLevel)
    local generation = rule and rule[7];
    if (not generation) then return nil; end
    if (characterLevel < generation[1]) then
        return nil, "Character level is below this reward's generation range.";
    end
    local atLevel = math.min(characterLevel, generation[2]);
    local level = generation[4][atLevel - generation[1] + 1];
    if (not level or level < 1) then return nil, "Reward item-level progression is unavailable."; end
    return level, level + generation[3], atLevel;
end

function StatCapsBestGear.Load()
    local loaded, err = StatCapsItemDatabase.Load();
    if (not loaded) then return nil, err; end
    if (type(StatCapsGearRules) ~= "table") then
        local ok, loadError = pcall(import, "StatCaps.GearRules");
        if (not ok or type(StatCapsGearRules) ~= "table") then
            return nil, "Experimental equip rules could not be loaded: "
                .. tostring(loadError or "StatCaps.GearRules did not initialize StatCapsGearRules. Reload StatCaps.");
        end
    end
    if (type(StatCapsItemSources) ~= "table" or type(StatCapsSourceDescriptions) ~= "table") then
        local ok, loadError = pcall(import, "StatCaps.ItemSources");
        if (not ok or type(StatCapsItemSources) ~= "table") then
            return nil, "Item sources could not be loaded: " .. tostring(loadError);
        end
    end
    return true;
end

function StatCapsBestGear.Run(calc, context, state, options, progress)
    options = options or {};
    if (type(options) ~= "table") then return nil, "Invalid experimental search options."; end
    for _, key in ipairs({ "excludedIds", "excludedNames", "itemLevels", "pinned" }) do
        if (options[key] ~= nil and type(options[key]) ~= "table") then return nil, "Invalid experimental search options."; end
    end
    options = copy(options);
    local work = 0;
    local function tick(stage)
        work = work + 1;
        if (progress and work % 80 == 0) then progress(stage, work); end
    end
    if (type(calc) ~= "function" or not context or not context.snapshot or not context.profile
        or context.level ~= context.snapshot.level or not state) then
        return nil, "A supported character snapshot and selected build are required.";
    end
    local limits, err = StatCapsVirtues.Limits(context.level);
    if (not limits) then return nil, err; end
    local loaded;
    loaded, err = StatCapsBestGear.Load();
    if (not loaded) then return nil, err; end
    local currentVirtues;
    for id, level in pairs(options.itemLevels or {}) do
        local record = StatCapsItemRecords[id];
        if (not record or not record[7] or record[7][4] == "character" or type(level) ~= "number"
            or level % 1 ~= 0 or level < 1 or level > 999) then
            return nil, "Item-level overrides require an item-level scaling record and a whole level from 1 to 999.";
        end
    end
    currentVirtues, err = equippedVirtues(context.level, context.equippedVirtues);
    if (not currentVirtues) then return nil, err; end
    local original;
    original, err = StatCapsLoadouts.Equipment(state.original);
    if (not original) then return nil, err; end
    context = copy(context);
    context.armourType = calc(context.className .. "CDArmourType", context.level);
    if (type(context.armourType) ~= "number" or context.armourType < 1 or context.armourType > 3) then
        return nil, "Character armour proficiency is unavailable.";
    end
    local zero = StatCapsManual.Parse({});
    local removed = copy(currentVirtues);
    local currentSets;
    if (state.manualSetTotals) then
        currentSets, err = bonuses(state.extraOld);
    else
        local sets;
        sets, err = StatCapsSetDatabase.Calculate(original, context.level, state.manualSets);
        if (sets) then currentSets = sets.values; add(currentSets, state.extraOld); end
    end
    if (not currentSets) then return nil, err; end
    add(removed, currentSets);
    local mutable, kept, pools, usefulPools = {}, {}, {}, {};
    for _, slot in ipairs(StatCapsLoadouts.Slots) do
        local item = original[slot[1]];
        local weapon = slot[3] == "MAIN_HAND" or slot[3] == "OFF_HAND" or slot[3] == "RANGED_ITEM" or slot[3] == "CLASS";
        local legendary = item and item.id and StatCapsItemRecords[item.id] and StatCapsItemRecords[item.id][9];
        if (weapon and (not options.weapons or not item or legendary or not item.id or not item.values
            or (slot[3] ~= "CLASS" and not item.values.WeaponDPS and (StatCapsGearRules[item.id] or {})[3] ~= 4
                and (StatCapsGearRules[item.id] or {})[3] ~= 5 and (StatCapsGearRules[item.id] or {})[3] ~= 6))) then
            kept[slot[1]] = true;
        else
            mutable[slot[1]] = true;
            if (item) then
                if (not item.values) then return nil, "Enter the full current item bonuses first: " .. slot[2]; end
                local values;
                values, err = bonuses(item.values);
                if (not values) then return nil, slot[2] .. ": " .. err; end
                if (item.characterLevel and item.characterLevel ~= context.level) then
                    return nil, "Refresh the current scaling item for this character level: " .. slot[2];
                end
                add(removed, values);
            end
            pools[slot[1]] = {};
            usefulPools[slot[1]] = {};
        end
    end
    local calls = {};
    local function cachedCalc(key, level)
        local cacheKey = key .. ":" .. tostring(level);
        if (calls[cacheKey] == nil) then calls[cacheKey] = calc(key, level); end
        return calls[cacheKey];
    end
    local empty = StatCapsComparison.Capture(context.snapshot.samples, context.snapshot.attributes, 0, 0);
    empty.level = context.level;
    for _, sample in pairs(empty.samples) do sample.rating = 0; end
    for key in pairs(empty.attributes) do empty.attributes[key] = 0; end
    local subtraction = StatCapsManual.Project(cachedCalc, context.className, empty, zero, removed);
    for key, sample in pairs(context.snapshot.samples) do
        if (sample.valid and subtraction.samples[key].rating > sample.rating + 0.01) then
            return nil, "Current item/set/virtue totals exceed the captured " .. sample.label .. ". Correct the baseline first.";
        end
    end
    for key, value in pairs(context.snapshot.attributes) do
        if (subtraction.attributes[key] > value + 0.01) then return nil, "Current bonus totals exceed captured " .. key .. "."; end
    end
    if (subtraction.morale >= context.snapshot.morale or subtraction.armour > context.snapshot.armour + 0.01) then
        return nil, "Current bonus totals exceed captured morale or armour. Correct the baseline first.";
    end
    local base = StatCapsManual.Project(cachedCalc, context.className, context.snapshot, removed, zero);
    local function vector(values)
        return StatCapsManual.Project(cachedCalc, context.className, empty, zero, values);
    end
    local function projected(total)
        local result = StatCapsComparison.Capture(base.samples, base.attributes, base.morale, base.armour);
        result.level = context.level;
        result.morale, result.armour = result.morale + total.morale, result.armour + total.armour;
        for key in pairs(result.attributes) do result.attributes[key] = result.attributes[key] + total.attributes[key]; end
        for key, sample in pairs(result.samples) do sample.rating = sample.rating + total.samples[key].rating; end
        return result;
    end
    local function optimizeVirtues(snapshot)
        local candidates = {};
        if (limits.rank > 0) then
            for _, virtue in ipairs(StatCapsVirtueData.virtues) do
                local values = bonuses(virtue.ranks[limits.rank]);
                candidates[#candidates + 1] = { name = virtue.name, rank = limits.rank, values = values,
                    contribution = vector(values) };
            end
        end
        local total = copy(empty);
        local chosen, best, bestScore, scoreError = {}, {}, -math.huge, nil;
        local function contribute(candidate, factor)
            total.morale = total.morale + candidate.contribution.morale * factor;
            total.armour = total.armour + candidate.contribution.armour * factor;
            for key in pairs(total.attributes) do
                total.attributes[key] = total.attributes[key] + candidate.contribution.attributes[key] * factor;
            end
            for key, sample in pairs(total.samples) do
                sample.rating = sample.rating + candidate.contribution.samples[key].rating * factor;
            end
        end
        local function search(start, remaining)
            if (remaining == 0) then
                local trial = StatCapsComparison.Capture(snapshot.samples, snapshot.attributes, snapshot.morale, snapshot.armour);
                trial.level = context.level;
                trial.morale, trial.armour = trial.morale + total.morale, trial.armour + total.armour;
                for key in pairs(trial.attributes) do trial.attributes[key] = trial.attributes[key] + total.attributes[key]; end
                for key, sample in pairs(trial.samples) do sample.rating = sample.rating + total.samples[key].rating; end
                local score, _, err = StatCapsComparison.Score(context.profile, context.snapshot, trial);
                if (not score) then scoreError = err; return; end
                if (score > bestScore + 0.000000001) then
                    bestScore, best = score, {};
                    for i, candidate in ipairs(chosen) do best[i] = candidate; end
                end
                tick("Optimizing maximum-rank virtues");
                return;
            end
            for i = start, #candidates - remaining + 1 do
                local candidate = candidates[i];
                chosen[#chosen + 1] = candidate; contribute(candidate, 1);
                search(i + 1, remaining - 1);
                contribute(candidate, -1); chosen[#chosen] = nil;
                if (scoreError) then return; end
            end
        end
        search(1, math.min(limits.slots, #candidates));
        if (scoreError) then return nil, scoreError; end
        local values = copy(zero);
        for _, candidate in ipairs(best) do add(values, candidate.values); end
        return { choices = best, values = values, projected = StatCapsManual.Project(cachedCalc, context.className, snapshot, zero, values) };
    end
    local ideal;
    ideal, err = optimizeVirtues(StatCapsManual.Project(cachedCalc, context.className, context.snapshot, currentVirtues, zero));
    if (not ideal) then return nil, err; end
    local virtueValues = ideal.values;
    local coefficients = {};
    local reference = StatCapsComparison.Capture(context.snapshot.samples, context.snapshot.attributes,
        context.snapshot.morale, context.snapshot.armour);
    reference.level = context.level;
    for _, sample in pairs(reference.samples) do sample.rating = 0; end
    for _, field in ipairs(StatCapsManual.Fields) do
        if (field[1] ~= "WeaponDPS") then
            local unit = copy(zero); unit[field[1]] = 1;
            local unitSnapshot = StatCapsManual.Project(cachedCalc, context.className, reference, zero, unit);
            local score, _, scoreError = StatCapsComparison.Score(context.profile, reference, unitSnapshot);
            if (not score) then return nil, scoreError; end
            coefficients[field[1]] = score;
        end
    end
    local function priority(values)
        local score = 0;
        for key, coefficient in pairs(coefficients) do score = score + (values[key] or 0) * coefficient; end
        return score;
    end
    local function stronger(a, b)
        if (math.abs(a.priority - b.priority) > 0.000000001) then return a.priority > b.priority; end
        return (a.id or 0) < (b.id or 0);
    end
    local function retain(pool, candidate)
        pool[#pool + 1] = candidate;
        table.sort(pool, stronger);
        if (#pool > 32) then table.remove(pool); end
    end
    local allBySlot, count, skipped, unsourced = {}, 0, 0, 0;
    local ids = {};
    for id in pairs(StatCapsItemRecords) do ids[#ids + 1] = id; end
    table.sort(ids);
    for _, slot in ipairs(StatCapsLoadouts.Slots) do allBySlot[slot[1]] = {}; end
    for _, id in ipairs(ids) do
        local record, rule = StatCapsItemRecords[id], StatCapsGearRules[id];
        -- Items without any known LOTRO Companion source are usually removed or never released.
        if (not options.includeUnsourced and not StatCapsItemSources[id]) then
            unsourced = unsourced + 1;
        elseif (not (options.excludedIds or {})[id] and not (options.excludedNames or {})[record[1]]) then
            local possible = {};
            for _, slot in ipairs(StatCapsLoadouts.Slots) do
                if (mutable[slot[1]] and StatCapsBestGear.Eligible(record, rule, slot, context, options, original[slot[1]])) then
                    possible[#possible + 1] = slot;
                end
            end
            if (#possible > 0) then
                local override = (options.itemLevels or {})[id];
                local generated, maximum, generatedAt = StatCapsBestGear.GeneratedLevel(rule, context.level);
                local values, level;
                if (override or not rule[7] or generated) then
                    values, level = StatCapsItemDatabase.Values(record, override or generated, context.level);
                end
                if (values) then
                    local parsed = bonuses(values);
                    if (not parsed) then return nil, "Invalid numeric item bonuses for ID " .. id; end
                    local candidate = { id = id, name = record[1], category = record[3], slot = record[6], values = parsed,
                        itemLevel = record[7] and record[7][4] == "character" and record[2] or level,
                        characterLevel = record[7] and record[7][4] == "character" and context.level or nil,
                        restrictions = record[8], priority = priority(parsed), rule = rule,
                        generatedLevel = generated, generatedMaximum = generated and maximum or nil,
                        generatedAt = generatedAt };
                    count = count + 1;
                    for _, slot in ipairs(possible) do
                        local worn = original[slot[1]];
                        if (not worn or not worn.values or not worn.values.WeaponDPS
                            or (parsed.WeaponDPS and parsed.WeaponDPS >= worn.values.WeaponDPS)) then
                            allBySlot[slot[1]][#allBySlot[slot[1]] + 1] = candidate;
                            retain(pools[slot[1]], candidate);
                            local preview = StatCapsManual.Project(cachedCalc, context.className, ideal.projected,
                                worn and bonuses(worn.values) or zero, parsed);
                            local score, _, scoreError = StatCapsComparison.Score(context.profile, context.snapshot, preview);
                            if (not score) then return nil, scoreError; end
                            local useful = usefulPools[slot[1]];
                            useful[#useful + 1] = { item = candidate, score = score };
                            table.sort(useful, function(a, b)
                                if (math.abs(a.score - b.score) > 0.000000001) then return a.score > b.score; end
                                return stronger(a.item, b.item);
                            end);
                            if (#useful > 16) then table.remove(useful); end
                        end
                    end
                else
                    if ((options.itemLevels or {})[id]) then return nil, record[1] .. ": " .. tostring(level); end
                    skipped = skipped + 1;
                end
            end
        end
        tick("Scanning eligible items");
    end
    local plan = copy(original);
    local function excluded(item)
        return item and (((options.excludedIds or {})[item.id]) or (options.excludedNames or {})[item.name]);
    end
    for _, slot in ipairs(StatCapsLoadouts.Slots) do
        if (mutable[slot[1]]) then
            local pool = pools[slot[1]];
            local seen = {};
            for _, candidate in ipairs(pool) do seen[candidate] = true; end
            for _, row in ipairs(usefulPools[slot[1]]) do
                if (not seen[row.item]) then pool[#pool + 1] = row.item; seen[row.item] = true; end
            end
            -- Include a representative for every scored stat, not just the highest uncapped totals.
            for field, coefficient in pairs(coefficients) do
                if (coefficient > 0) then
                    local best;
                    for _, candidate in ipairs(allBySlot[slot[1]]) do
                        if (not best or candidate.values[field] > best.values[field]
                            or (candidate.values[field] == best.values[field] and stronger(candidate, best))) then best = candidate; end
                    end
                    if (best and not seen[best]) then pool[#pool + 1] = best; seen[best] = true; end
                end
            end
            local item = plan[slot[1]];
            local currentEligible = item and not item.id;
            if (item and item.id and StatCapsItemRecords[item.id]) then
                currentEligible = StatCapsBestGear.Eligible(StatCapsItemRecords[item.id], StatCapsGearRules[item.id],
                    slot, context, { unverified = true, weapons = options.weapons }, original[slot[1]]);
            end
            if (item and not excluded(item) and currentEligible) then
                item.priority, item.current = priority(item.values), true;
                pool[#pool + 1] = item;
            else plan[slot[1]] = nil; end
            local pin = (options.pinned or {})[slot[1]];
            if (pin) then
                local chosen;
                for _, candidate in ipairs(allBySlot[slot[1]]) do if (candidate.id == pin) then chosen = candidate; break; end end
                if (not chosen) then return nil, "The pinned item is excluded, ineligible or unsupported for: " .. slot[2]; end
                plan[slot[1]] = chosen;
                if (not seen[chosen]) then pools[slot[1]][#pools[slot[1]] + 1] = chosen; end
            end
            table.sort(pools[slot[1]], stronger);
        end
    end
    local function legal(items)
        local seen, unique = {}, {};
        for key, item in pairs(items) do
            local identity = item.id or item.name;
            seen[identity] = (seen[identity] or 0) + 1;
            local rule = item.restrictions or {};
            if (rule.unique) then unique[identity] = true; end
            if (rule.precludedSlot) then
                for otherKey, other in pairs(items) do
                    local canonical;
                    for _, slot in ipairs(StatCapsLoadouts.Slots) do if (slot[1] == otherKey) then canonical = slot[3]; break; end end
                    if (key ~= otherKey and (canonical or other.slot) == rule.precludedSlot) then return false; end
                end
            end
        end
        for identity in pairs(unique) do if (seen[identity] > 1) then return false; end end
        return true;
    end
    local lastError;
    local function evaluate(items, virtues)
        if (not legal(items)) then return nil; end
        local sets, setError = StatCapsSetDatabase.Calculate(items, context.level);
        if (not sets or #sets.unknown > 0) then
            lastError = setError or ("Unknown set membership: " .. table.concat(sets.unknown, ", "));
            return nil;
        end
        local values = copy(virtues);
        add(values, sets.values);
        for key, item in pairs(items) do if (mutable[key]) then add(values, item.values); end end
        local snapshot = projected(vector(values));
        local score, _, scoreError = StatCapsComparison.Score(context.profile, context.snapshot, snapshot);
        if (not score) then lastError = scoreError; return nil; end
        return score, snapshot, sets, values;
    end
    local bestScore = evaluate(plan, virtueValues);
    if (not bestScore) then
        for key in pairs(mutable) do if (not (options.pinned or {})[key]) then plan[key] = nil; end end
        bestScore = evaluate(plan, virtueValues);
        if (not bestScore) then return nil, lastError or "No legal starting gear combination found."; end
    end
    -- Try complete set families as well as individual swaps; a set can pay off only after several changes.
    local families = {};
    for key in pairs(mutable) do
        for _, candidate in ipairs(allBySlot[key]) do
            local membership = StatCapsSetItems[candidate.id];
            for _, id in ipairs(membership and membership.sets or {}) do
                families[id] = families[id] or {};
                local pool = families[id][key] or {};
                families[id][key] = pool;
                retain(pool, candidate);
                if (#pool > 3) then table.remove(pool); end
            end
            tick("Checking equipment-set families");
        end
    end
    local familyIds = {};
    for id in pairs(families) do familyIds[#familyIds + 1] = id; end
    table.sort(familyIds);
    for _, id in ipairs(familyIds) do
        local trial, used = {}, {};
        for key, item in pairs(plan) do trial[key] = item; end
        for _, slot in ipairs(StatCapsLoadouts.Slots) do
            if (not (options.pinned or {})[slot[1]]) then
                for _, candidate in ipairs(families[id][slot[1]] or {}) do
                    if (not used[candidate.id]) then trial[slot[1]], used[candidate.id] = candidate, true; break; end
                end
            end
        end
        local score = evaluate(trial, virtueValues);
        if (score and score > bestScore + 0.000000001) then plan, bestScore = trial, score; end
        tick("Checking equipment-set families");
    end
    for cycle = 1, 3 do
        for pass = 1, 3 do
            local changed = false;
            for _, slot in ipairs(StatCapsLoadouts.Slots) do
                if (mutable[slot[1]] and not (options.pinned or {})[slot[1]]) then
                    local previous, chosen = plan[slot[1]], plan[slot[1]];
                    for _, candidate in ipairs(pools[slot[1]]) do
                        plan[slot[1]] = candidate;
                        local score = evaluate(plan, virtueValues);
                        if (score and (score > bestScore + 0.000000001 or
                            (not chosen and score >= bestScore - 0.000000001 and candidate.priority > 0))) then
                            bestScore, chosen, changed = score, candidate, true;
                        end
                        tick("Balancing gear and set bonuses");
                    end
                    plan[slot[1]] = chosen or previous;
                end
            end
            if (not changed) then break; end
        end
        local score, snapshot = evaluate(plan, zero);
        if (not score) then return nil, lastError or "No legal gear combination found."; end
        ideal, err = optimizeVirtues(snapshot);
        if (not ideal) then return nil, err; end
        virtueValues = ideal.values;
        bestScore = evaluate(plan, virtueValues);
        tick("Optimizing maximum-rank virtues");
    end
    local score, snapshot, sets = evaluate(plan, virtueValues);
    if (not score) then return nil, lastError or "No legal gear combination found."; end
    local alternatives = {};
    for _, slot in ipairs(StatCapsLoadouts.Slots) do
        local rows, seen = {}, {};
        local selected = plan[slot[1]];
        if (mutable[slot[1]] and selected) then
            local present = false;
            for _, candidate in ipairs(pools[slot[1]]) do if (candidate == selected) then present = true; break; end end
            if (not present) then pools[slot[1]][#pools[slot[1]] + 1] = selected; end
        end
        for _, candidate in ipairs(pools[slot[1]] or {}) do
            if (not seen[candidate.id or candidate.name]) then
                local previous = plan[slot[1]]; plan[slot[1]] = candidate;
                local alternateScore = evaluate(plan, virtueValues);
                plan[slot[1]] = previous;
                if (alternateScore) then
                    rows[#rows + 1] = { item = candidate, score = alternateScore };
                    seen[candidate.id or candidate.name] = true;
                end
                tick("Preparing alternatives");
            end
        end
        table.sort(rows, function(a, b)
            if (math.abs(a.score - b.score) > 0.000000001) then return a.score > b.score; end
            return stronger(a.item, b.item);
        end);
        alternatives[slot[1]] = rows;
    end
    return { equipment = plan, projected = snapshot, score = score, virtues = ideal.choices, limits = limits,
        alternatives = alternatives, kept = kept, scanned = count, skipped = skipped, unsourced = unsourced, sets = sets,
        context = context, options = options };
end
