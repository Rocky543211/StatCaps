StatCapsLoadouts = {};
StatCapsLoadouts.Slots = {
    { "Head", "Head", "HEAD" }, { "Shoulder", "Shoulders", "SHOULDER" },
    { "Back", "Back", "BACK" }, { "Chest", "Chest", "CHEST" },
    { "Gloves", "Hands", "HAND" }, { "Legs", "Legs", "LEGS" },
    { "Boots", "Feet", "FEET" }, { "Necklace", "Necklace", "NECK" },
    { "Earring1", "Earring 1", "EAR" }, { "Earring2", "Earring 2", "EAR" },
    { "Bracelet1", "Bracelet 1", "WRIST" }, { "Bracelet2", "Bracelet 2", "WRIST" },
    { "Ring1", "Ring 1", "FINGER" }, { "Ring2", "Ring 2", "FINGER" },
    { "Pocket", "Pocket", "POCKET" }, { "PrimaryWeapon", "Main hand", "MAIN_HAND" },
    { "SecondaryWeapon", "Off hand", "OFF_HAND" },
    { "RangedWeapon", "Ranged weapon", "RANGED_ITEM" }, { "Class", "Class item", "CLASS" }
};
local slotAliases = {
    EAR = { LEFT_EAR = true, RIGHT_EAR = true }, WRIST = { LEFT_WRIST = true, RIGHT_WRIST = true },
    FINGER = { LEFT_FINGER = true, RIGHT_FINGER = true }, MAIN_HAND = { EITHER_HAND = true },
    OFF_HAND = { EITHER_HAND = true }, CLASS = { CLASS_SLOT = true }
};
-- Source data uses broader slot codes (EITHER_HAND, LEFT_EAR, CLASS_SLOT) than the planner's slots.
function StatCapsLoadouts.SlotFits(plannerSlot, itemSlot)
    return itemSlot == plannerSlot or (slotAliases[plannerSlot] or {})[itemSlot] == true;
end

local slotDefinitions = {};
for _, slot in ipairs(StatCapsLoadouts.Slots) do slotDefinitions[slot[1]] = slot; end

local function copy(source)
    if (type(source) ~= "table") then return source; end
    local result = {};
    for key, value in pairs(source) do result[key] = copy(value); end
    return result;
end

function StatCapsLoadouts.IconLayers(info)
    if (not info) then return nil; end
    local layers = {};
    for key, method in pairs({ back = "GetBackgroundImageID", under = "GetUnderlayImageID",
        shadow = "GetShadowImageID" }) do
        if (type(info[method]) == "function") then
            local ok, value = pcall(info[method], info);
            if (ok and type(value) == "number" and value ~= 0) then layers[key] = value; end
        end
    end
    return next(layers) and layers or nil;
end

function StatCapsLoadouts.CopyItem(item)
    if (not item) then return nil; end
    return {
        name = item.name, slot = item.slot, category = item.category, icon = item.icon, iconLayers = copy(item.iconLayers), values = copy(item.values),
        confirmed = item.confirmed == true, id = item.id, itemLevel = item.itemLevel,
        reviewed = item.reviewed == true, suggested = item.suggested == true,
        characterLevel = item.characterLevel, restrictions = copy(item.restrictions),
        setId = item.setId, noSet = item.noSet == true, removed = item.removed == true
    };
end

local bonusKeys, equipmentSlots = {}, {};
for _, field in ipairs(StatCapsManual.Fields) do bonusKeys[field[1]] = true; end
for _, slot in ipairs(StatCapsLoadouts.Slots) do equipmentSlots[slot[3]] = true; end
local function whole(value, maximum)
    return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= maximum;
end
local function validBonuses(values)
    if (values == nil) then return true; end
    if (type(values) ~= "table") then return false; end
    for key, value in pairs(values) do
        if (not bonusKeys[key] or type(value) ~= "number" or value ~= value or value < 0
            or value == math.huge or (key ~= "WeaponDPS" and value % 1 ~= 0)) then return false; end
    end
    return true;
end
local function validItem(item)
    if (type(item) ~= "table") then return false; end
    if (item.removed == true) then
        return item.values == nil and item.restrictions == nil
            and (item.name == nil or type(item.name) == "string")
            and (item.slot == nil or equipmentSlots[item.slot]);
    end
    if (type(item.name) ~= "string" or item.name == "" or not equipmentSlots[item.slot]
        or not validBonuses(item.values)) then return false; end
    for _, field in ipairs({ "reviewed", "suggested" }) do
        if (item[field] ~= nil and type(item[field]) ~= "boolean") then return false; end
    end
    for _, field in ipairs({ { "id", 4294967295 }, { "category", 4294967295 },
        { "itemLevel", 999 }, { "characterLevel", 160 }, { "setId", 4294967295 } }) do
        if (item[field[1]] ~= nil and not whole(item[field[1]], field[2])) then return false; end
    end
    if (item.restrictions ~= nil) then
        local restrictions = item.restrictions;
        if (type(restrictions) ~= "table" or (restrictions.className ~= nil and type(restrictions.className) ~= "string")
            or (restrictions.minimum ~= nil and not whole(restrictions.minimum, 160))
            or (restrictions.precludedSlot ~= nil and not equipmentSlots[restrictions.precludedSlot])
            or (restrictions.unique ~= nil and type(restrictions.unique) ~= "boolean")) then return false; end
        for key in pairs(restrictions) do
            if (key ~= "className" and key ~= "minimum" and key ~= "precludedSlot" and key ~= "unique") then
                return false;
            end
        end
    end
    return item.noSet == nil or type(item.noSet) == "boolean";
end

function StatCapsLoadouts.Equipment(source)
    if (type(source) ~= "table") then return nil, "Equipment snapshot is unavailable."; end
    local equipment = {};
    local used, canonicalSlots = {}, {};
    for _, slot in ipairs(StatCapsLoadouts.Slots) do
        local item = source[slot[1]];
        if (item) then
            if (not validItem(item) or item.removed or item.slot ~= slot[3]) then
                return nil, "Invalid equipment entry: " .. slot[2];
            end
            equipment[slot[1]] = StatCapsLoadouts.CopyItem(item);
            used[item], canonicalSlots[slot[3]] = true, true;
        end
    end
    for _, slot in ipairs(StatCapsLoadouts.Slots) do
        if (not equipment[slot[1]]) then
            local legacy = source[slot[3]] or (slot[3] == "OFF_HAND" and source.Shield);
            if (legacy and not used[legacy] and not canonicalSlots[slot[3]]) then
                local normalized = StatCapsLoadouts.CopyItem(type(legacy) == "table" and legacy);
                if (normalized) then normalized.slot = slot[3]; end
                if (not validItem(normalized)) then return nil, "Invalid equipment entry: " .. slot[2]; end
                equipment[slot[1]] = normalized;
                used[legacy] = true;
                equipment[slot[1]].slot = slot[3];
            end
        end
    end
    return equipment;
end

function StatCapsLoadouts.New(equipment, saved)
    local original, err = StatCapsLoadouts.Equipment(equipment);
    if (not original) then return nil, err; end
    local state = { original = original, replacements = {},
        manualSets = {}, extraOld = {}, extraNew = {}, setsConfirmed = false, extrasConfirmed = false,
        manualSetTotals = false, extraOldConfirmed = false, extraNewConfirmed = false };
    state.source = StatCapsLoadouts.Equipment(equipment);
    if (saved ~= nil) then
        if (type(saved) ~= "table") then return nil, "Saved loadout plan is invalid."; end
        if (saved.manualSetTotals ~= nil and type(saved.manualSetTotals) ~= "boolean") then
            return nil, "Saved loadout plan is invalid.";
        end
        state.manualSetTotals = saved.manualSetTotals == true;
        for _, key in ipairs({ "manualSets", "original", "replacements", "extraOld", "extraNew" }) do
            if (saved[key] ~= nil and type(saved[key]) ~= "table") then return nil, "Saved loadout plan is invalid."; end
        end
        if (not validBonuses(saved.extraOld) or not validBonuses(saved.extraNew)) then
            return nil, "Saved manual set bonuses are invalid.";
        end
        for id, enabled in pairs(saved.manualSets or {}) do
            if (not whole(id, 4294967295) or type(enabled) ~= "boolean") then
                return nil, "Saved manual set selection is invalid.";
            end
        end
        state.manualSets = copy(saved.manualSets or {});
        state.extraOld, state.extraNew = copy(saved.extraOld or {}), copy(saved.extraNew or {});
        for key, item in pairs(saved.replacements or {}) do
            if (not slotDefinitions[key] or not validItem(item)
                or (not item.removed and item.slot ~= slotDefinitions[key][3])) then
                return nil, "Saved loadout item is invalid.";
            end
            state.replacements[key] = StatCapsLoadouts.CopyItem(item);
            state.replacements[key].confirmed = false;
        end
        for key, item in pairs(saved.original or {}) do
            if (not slotDefinitions[key] or not validItem(item) or item.slot ~= slotDefinitions[key][3]) then
                return nil, "Saved equipped item is invalid.";
            end
            local current = state.original[key];
            if (current and current.name == item.name and (current.suggested or not current.id or current.id == item.id)
                and (not current.category or current.category == item.category)
                and (current.suggested or not current.itemLevel or not item.itemLevel or current.itemLevel == item.itemLevel)
                and (not current.characterLevel or current.characterLevel == item.characterLevel)) then
                state.original[key] = StatCapsLoadouts.CopyItem(item);
                state.original[key].reviewed = item.reviewed == true or item.confirmed == true;
                state.original[key].confirmed = false;
            end
        end
    end
    return state;
end

function StatCapsLoadouts.Planned(state)
    local result = {};
    for key, item in pairs(state.original) do result[key] = item; end
    for key, item in pairs(state.replacements) do
        result[key] = not item.removed and item or nil;
    end
    return result;
end

function StatCapsLoadouts.CompareVirtues(calc, context, result)
    local selection, err = StatCapsVirtues.Validate(context.level, context.equippedVirtues);
    if (not selection) then return nil, err; end
    local ranks;
    ranks, err = StatCapsVirtues.ValidateRanks(context.earnedVirtueRanks);
    if (not ranks) then return nil, err; end
    local current, planned;
    current, err = StatCapsVirtues.Recommend(calc, context.className, context.profile,
        context.snapshot, context.level, selection, ranks);
    if (not current) then return nil, err; end
    planned, err = StatCapsVirtues.Recommend(calc, context.className, context.profile,
        result.projected, context.level, selection, ranks);
    if (not planned) then return nil, err; end
    local total, _, scoreError = StatCapsComparison.Score(context.profile, context.snapshot, planned.projected);
    if (not total) then return nil, scoreError; end
    local baseline;
    baseline, _, scoreError = StatCapsComparison.Score(context.profile, context.snapshot, current.projected);
    if (not baseline) then return nil, scoreError; end
    return { current = current, planned = planned, total = total, optimizedDelta = total - baseline };
end

function StatCapsLoadouts.Serialize(state)
    local result = { original = {}, replacements = {}, manualSets = copy(state.manualSets),
        extraOld = copy(state.extraOld), extraNew = copy(state.extraNew), manualSetTotals = state.manualSetTotals };
    for key, item in pairs(state.original) do result.original[key] = StatCapsLoadouts.CopyItem(item); end
    for key, item in pairs(state.replacements) do result.replacements[key] = StatCapsLoadouts.CopyItem(item); end
    return result;
end

function StatCapsLoadouts.ReviewedEquipment(equipment, saved, level)
    if (not saved) then return {}; end
    local restored, err = StatCapsLoadouts.New(equipment, saved);
    if (not restored) then return nil, err; end
    local reviewed = {};
    for key, item in pairs(restored.original) do
        local stored = saved.original and saved.original[key];
        -- Older plans saved user-chosen variants without review flags; only skip automatic suggestions.
        if (stored and stored.values and (stored.suggested ~= true or stored.confirmed == true or stored.reviewed == true)
            and item.name == stored.name
            and item.category == stored.category and item.slot == stored.slot and item.id == stored.id
            and item.itemLevel == stored.itemLevel
            and (not item.characterLevel or item.characterLevel == level)) then
            reviewed[key] = StatCapsLoadouts.CopyItem(item);
            reviewed[key].confirmed = true;
        end
    end
    return reviewed;
end

local function itemValues(item, label, level)
    if (not item or item.removed) then return StatCapsManual.Parse({}); end
    if (not item.values) then
        return nil, "Missing item values for: " .. label;
    end
    if (item.characterLevel and item.characterLevel ~= level) then
        return nil, "Character level changed. Search this scaling item again and verify its bonuses: " .. label;
    end
    local text = {};
    for key, value in pairs(item.values) do text[key] = tostring(value); end
    return StatCapsManual.Parse(text);
end

local function add(total, values)
    for _, field in ipairs(StatCapsManual.Fields) do
        local key = field[1];
        if (key ~= "WeaponDPS") then total[key] = (total[key] or 0) + (values[key] or 0); end
    end
end

function StatCapsLoadouts.HasBonuses(values)
    for _, value in pairs(values) do if (value ~= 0) then return true; end end
    return false;
end

function StatCapsLoadouts.ExtrasVerified(state)
    if (state.extrasConfirmed) then return true; end
    local requireBoth = state.manualSetTotals or next(state.manualSets) ~= nil;
    return (state.extraOldConfirmed or (not requireBoth and not StatCapsLoadouts.HasBonuses(state.extraOld)))
        and (state.extraNewConfirmed or (not requireBoth and not StatCapsLoadouts.HasBonuses(state.extraNew)));
end

function StatCapsLoadouts.AllowsClass(restriction, className)
    local target = className:lower():gsub("%W", "");
    for name in restriction:gmatch("[^;]+") do
        local allowed = name:lower():gsub("%W", "");
        if (allowed == "corsair") then allowed = "mariner"; end
        if (allowed == target) then return true; end
    end
    return false;
end

function StatCapsLoadouts.Evaluate(calc, context, state)
    if (type(calc) ~= "function" or not context or not context.profile or not context.snapshot
        or context.level ~= context.snapshot.level) then
        return nil, "Loadout calculation requires a supported character, build and current snapshot.";
    end
    local planned = StatCapsLoadouts.Planned(state);
    local oldTotal, newTotal = StatCapsManual.Parse({}), StatCapsManual.Parse({});
    local changes, weapons, identities, uniqueItems = 0, {}, {}, {};
    for key, item in pairs(planned) do
        local restrictions = item.restrictions or {};
        if (restrictions.className and not StatCapsLoadouts.AllowsClass(restrictions.className, context.className)) then
            return nil, "Item is restricted to another class: " .. item.name;
        end
        if (restrictions.minimum and restrictions.minimum > context.level) then
            return nil, "Character level is too low for: " .. item.name;
        end
        if (restrictions.precludedSlot) then
            for otherKey, other in pairs(planned) do
                if (otherKey ~= key and other.slot == restrictions.precludedSlot) then
                    return nil, "This item excludes another occupied equipment slot: " .. item.name;
                end
            end
        end
        local identity = item.id or item.name;
        identities[identity] = (identities[identity] or 0) + 1;
        if (restrictions.unique) then uniqueItems[identity] = item.name; end
    end
    for identity, name in pairs(uniqueItems) do
        if (identities[identity] > 1) then return nil, "Unique item cannot be equipped twice: " .. name; end
    end
    for key, replacement in pairs(state.replacements) do
        local definition = slotDefinitions[key];
        if (not definition) then return nil, "Unknown loadout equipment slot."; end
        if (not replacement.removed and replacement.slot ~= definition[3]) then
            return nil, "Item does not fit the selected equipment slot: " .. definition[2];
        end
        local old, err = itemValues(state.original[key], definition[2] .. " / equipped", context.level);
        if (not old) then return nil, err; end
        local new;
        new, err = itemValues(replacement, definition[2] .. " / planned", context.level);
        if (not new) then return nil, err; end
        add(oldTotal, old);
        add(newTotal, new);
        changes = changes + 1;
        local line = StatCapsManual.DPSChange(old.WeaponDPS, new.WeaponDPS);
        if (not state.original[key] and new.WeaponDPS) then
            line = string.format("Weapon DPS: empty slot -> %.1f. Separate from stat points.", new.WeaponDPS);
        elseif (replacement.removed and old.WeaponDPS) then
            line = string.format("Weapon DPS: %.1f -> empty slot. Separate from stat points.", old.WeaponDPS);
        end
        if (line) then weapons[#weapons + 1] = { slot = definition[2], text = line }; end
    end
    local extras = StatCapsLoadouts.HasBonuses(state.extraOld) or StatCapsLoadouts.HasBonuses(state.extraNew);
    if (changes == 0 and not extras) then return nil, "Choose at least one planned replacement or unequipped slot."; end
    local oldSets, newSets, err;
    if (state.manualSetTotals) then
        oldSets = { values = {}, rows = {}, warnings = {}, unknown = {} };
        newSets = { values = {}, rows = {}, warnings = {}, unknown = {} };
    else
        oldSets, err = StatCapsSetDatabase.Calculate(state.original, context.level, state.manualSets);
        if (not oldSets) then return nil, err; end
        newSets, err = StatCapsSetDatabase.Calculate(planned, context.level, state.manualSets);
        if (not newSets) then return nil, err; end
    end
    if (#oldSets.unknown > 0 or #newSets.unknown > 0) then
        return nil, "Set membership is unknown. Assign a set or explicitly choose No equipment set for: "
            .. table.concat(#oldSets.unknown > 0 and oldSets.unknown or newSets.unknown, ", ");
    end
    if ((#oldSets.rows > 0 or #newSets.rows > 0 or #oldSets.unknown > 0 or #newSets.unknown > 0)
        and not state.setsConfirmed) then
        return nil, "Review set memberships and bonuses, then confirm Set bonuses checked.";
    end
    local manual = next(state.manualSets) ~= nil;
    if ((manual or extras or state.manualSetTotals) and not StatCapsLoadouts.ExtrasVerified(state)) then
        return nil, "Verify the current and planned manual set bonuses before calculating.";
    end
    for _, side in ipairs({ { oldTotal, oldSets.values, state.extraOld }, { newTotal, newSets.values, state.extraNew } }) do
        add(side[1], side[2]);
        local text = {};
        for key, value in pairs(side[3]) do text[key] = tostring(value); end
        local values;
        values, err = StatCapsManual.Parse(text);
        if (not values) then return nil, "Manual set bonuses: " .. err; end
        if (values.WeaponDPS) then return nil, "Set bonuses cannot be entered as weapon DPS."; end
        add(side[1], values);
    end
    local projected = StatCapsManual.Project(calc, context.className, context.snapshot, oldTotal, newTotal);
    local score, details, scoreError = StatCapsComparison.Score(context.profile, context.snapshot, projected);
    local result = StatCapsComparison.Evaluate(context.profile, context.snapshot, projected);
    result.score, result.scoreError, result.details = score, scoreError, details;
    result.projected, result.oldSets, result.newSets = projected, oldSets, newSets;
    result.oldTotal, result.newTotal, result.weapons, result.changes = oldTotal, newTotal, weapons, changes;
    result.hope = newTotal.Hope - oldTotal.Hope;
    return result;
end
