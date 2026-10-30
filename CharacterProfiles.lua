StatCapsCharacterProfiles = {};

local function number(value)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge;
end

local function copyNumbers(source)
    if (type(source) ~= "table") then return nil; end
    local result = {};
    for key, value in pairs(source) do
        if (type(key) == "string" and number(value)) then result[key] = value; end
    end
    return result;
end

local function copySnapshot(source)
    if (type(source) ~= "table" or type(source.samples) ~= "table"
        or type(source.attributes) ~= "table") then
        return nil, "Character snapshot is incomplete.";
    end
    local result = {
        samples = {}, attributes = copyNumbers(source.attributes),
        morale = number(source.morale) and source.morale or nil,
        armour = number(source.armour) and source.armour or nil,
        level = source.level
    };
    for key, sample in pairs(source.samples) do
        if (type(key) ~= "string" or type(sample) ~= "table"
            or not number(sample.rating) or not number(sample.limit)
            or type(sample.valid) ~= "boolean") then
            return nil, "Character snapshot contains an invalid rating.";
        end
        result.samples[key] = {
            label = type(sample.label) == "string" and sample.label or key,
            rating = sample.rating, limit = sample.limit, valid = sample.valid
        };
    end
    return result;
end

local function copyConfig(source)
    if (type(source) ~= "table") then return nil; end
    local result = {
        mode = source.mode, preset = source.preset,
        finesseTarget = source.finesseTarget,
        weights = copyNumbers(source.weights),
        references = copyNumbers(source.references),
        roleWeights = copyNumbers(source.roleWeights)
    };
    return result;
end

local function copyItems(source)
    local result = {};
    if (type(source) ~= "table") then return result; end
    for slot, item in pairs(source) do
        if (type(slot) == "string" and type(item) == "table"
            and type(item.name) == "string") then
            local values = copyNumbers(item.values);
            if (values or item.confirmed == false) then
                result[slot] = {
                    name = item.name, slot = type(item.slot) == "string" and item.slot or slot,
                    icon = number(item.icon) and item.icon or nil,
                    iconLayers = type(item.iconLayers) == "table" and copyNumbers(item.iconLayers) or nil,
                    category = item.category, label = type(item.label) == "string" and item.label or slot,
                    values = values, confirmed = values ~= nil and item.confirmed ~= false,
                    manual = item.manual == true or (values ~= nil and item.confirmed ~= false),
                    lookup = type(item.lookup) == "string" and item.lookup or nil,
                    id = number(item.id) and item.id or nil,
                    itemLevel = number(item.itemLevel) and item.itemLevel or nil,
                    restrictions = type(item.restrictions) == "table" and {
                        className = type(item.restrictions.className) == "string" and item.restrictions.className or nil,
                        minimum = number(item.restrictions.minimum) and item.restrictions.minimum or nil,
                        precludedSlot = type(item.restrictions.precludedSlot) == "string" and item.restrictions.precludedSlot or nil,
                        unique = item.restrictions.unique == true
                    } or nil,
                    characterLevel = number(item.characterLevel) and item.characterLevel or nil
                };
            end
        end
    end
    return result;
end

local function copyVirtues(source)
    if (type(source) ~= "table") then return nil; end
    local result = {};
    for index = 1, 5 do
        local choice = source[index];
        if (choice ~= nil) then
            if (type(choice) ~= "table" or type(choice.name) ~= "string"
                or not number(choice.rank) or choice.rank % 1 ~= 0 or choice.rank < 1 or choice.rank > 100) then
                return nil;
            end
            result[index] = { name = choice.name, rank = choice.rank };
        end
    end
    return result;
end

function StatCapsCharacterProfiles.Put(profiles, key, source)
    if (type(profiles) ~= "table" or type(key) ~= "string" or key == ""
        or type(source) ~= "table" or type(source.className) ~= "string"
        or type(source.level) ~= "number" or source.level < 1 or source.level > 160
        or source.level % 1 ~= 0) then
        return nil, "Character profile identity or level is invalid.";
    end
    local snapshot, err = copySnapshot(source.snapshot);
    if (not snapshot) then return nil, err; end
    snapshot.level = source.level;
    profiles[key] = {
        name = type(source.name) == "string" and source.name or key,
        className = source.className, level = source.level,
        build = type(source.build) == "string" and source.build or nil,
        tier = type(source.tier) == "number" and source.tier % 1 == 0
            and source.tier >= 1 and source.tier <= 4 and source.tier or 1,
        scoring = copyConfig(source.scoring), snapshot = snapshot,
        items = copyItems(source.items), equipmentCaptured = source.equipmentCaptured == true,
        virtues = copyVirtues(source.virtues), virtueRanks = copyNumbers(source.virtueRanks)
    };
    return profiles[key];
end

function StatCapsCharacterProfiles.Normalize(source)
    local result = {};
    for key, profile in pairs(type(source) == "table" and source or {}) do
        if (type(profile) == "table") then
            StatCapsCharacterProfiles.Put(result, key, profile);
        end
    end
    return result;
end

function StatCapsCharacterProfiles.PutItem(profiles, key, equipmentSlot, name, values, category, characterLevel, equipmentKey)
    local profile = type(profiles) == "table" and profiles[key];
    if (type(profile) ~= "table") then
        return nil, "Log in to this character once to create its saved profile.";
    end
    if (type(equipmentSlot) ~= "string" or equipmentSlot == ""
        or type(name) ~= "string" or type(values) ~= "table") then
        return nil, "Equipped item identity or bonuses are incomplete.";
    end
    if (characterLevel ~= nil and (not number(characterLevel) or characterLevel % 1 ~= 0
        or characterLevel < 1 or characterLevel > 160)) then
        return nil, "A character level from 1 to 160 is required for this item.";
    end
    local copied = copyNumbers(values);
    if (not copied) then return nil, "Equipped item bonuses are invalid."; end
    profile.items = copyItems(profile.items);
    equipmentKey = type(equipmentKey) == "string" and equipmentKey or equipmentSlot;
    local previous = profile.items[equipmentKey];
    profile.items[equipmentKey] = {
        name = name, slot = equipmentSlot, category = category, values = copied,
        characterLevel = characterLevel, confirmed = true, manual = true,
        label = previous and previous.label or equipmentKey,
        id = previous and previous.name == name and previous.id or nil,
        itemLevel = previous and previous.name == name and previous.itemLevel or nil,
        restrictions = previous and previous.name == name and previous.restrictions or nil
    };
    return profile.items[equipmentKey];
end

function StatCapsCharacterProfiles.CaptureEquipment(previous, equipped, level)
    previous = copyItems(previous);
    local result = {};
    for _, item in ipairs(equipped) do
        local name, category = item.info:GetName(), item.info:GetCategory();
        local values, message, _, _, characterLevel, id, itemLevel, restrictions =
            StatCapsItemDatabase.Lookup(nil, item.info, level);
        local old = previous[item.key];
        if (not old) then
            local legacy = previous[item.equipmentSlot]
                or (item.equipmentSlot == "OFF_HAND" and previous.Shield);
            local count = 0;
            for _, worn in ipairs(equipped) do
                if (worn.equipmentSlot == item.equipmentSlot) then count = count + 1; end
            end
            if (count == 1) then old = legacy; end
        end
        if (old and old.manual and old.name == name and old.category == category
            and (not old.characterLevel or old.characterLevel == level)) then
            values, characterLevel = old.values, old.characterLevel;
            message = "Previously entered bonuses. Item instance is not verified; check bonuses before confirming.";
        end
        result[item.key] = {
            name = name, category = category, slot = item.equipmentSlot, label = item.label,
            icon = type(item.info.GetIconImageID) == "function" and item.info:GetIconImageID() or nil,
            iconLayers = StatCapsLoadouts and StatCapsLoadouts.IconLayers and StatCapsLoadouts.IconLayers(item.info) or nil,
            values = values, characterLevel = characterLevel, confirmed = false,
            id = id, itemLevel = itemLevel, restrictions = restrictions,
            manual = old and old.manual and old.name == name and old.category == category
                and (not old.characterLevel or old.characterLevel == level) or false,
            lookup = message
        };
    end
    return result;
end

function StatCapsCharacterProfiles.MatchingItems(items, equipmentSlot)
    local matches = {};
    for key, item in pairs(type(items) == "table" and items or {}) do
        local slot = item.slot == "Shield" and "OFF_HAND" or item.slot;
        if (slot == equipmentSlot) then
            matches[#matches + 1] = { key = key, item = item };
        end
    end
    table.sort(matches, function(a, b) return a.key < b.key; end);
    return matches;
end

function StatCapsCharacterProfiles.Get(profiles, key)
    if (type(profiles) ~= "table" or type(key) ~= "string") then return nil; end
    local source = profiles[key];
    if (type(source) ~= "table") then return nil; end
    local normalized = {};
    if (not StatCapsCharacterProfiles.Put(normalized, key, source)) then return nil; end
    return normalized[key];
end

function StatCapsCharacterProfiles.List(profiles)
    local result = {};
    for key, profile in pairs(type(profiles) == "table" and profiles or {}) do
        if (type(key) == "string" and type(profile) == "table"
            and type(profile.name) == "string" and type(profile.className) == "string"
            and type(profile.snapshot) == "table") then
            result[#result + 1] = { key = key, profile = profile };
        end
    end
    table.sort(result, function(a, b)
        if (a.profile.name == b.profile.name) then return a.key < b.key; end
        return a.profile.name < b.profile.name;
    end);
    return result;
end
