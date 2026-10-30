StatCapsRatings = {};

local penetrationStats = {
    Mit = "TpenArmour",
    BPE = "TpenBPE",
    Resist = "TpenResist"
};

function StatCapsRatings.Calculate(calc, stat, prefix, level, tier, rating)
    assert(level >= 1 and level <= 160, "CalcStat data supports levels 1-160 only.");
    local cap = calc(prefix .. "PRatPCapR", level);
    assert(type(cap) == "number" and cap > 0, "Missing cap data for " .. prefix);
    local penetration = 0;
    local penetrationStat = penetrationStats[stat];
    if (tier >= 2 and penetrationStat) then
        -- CalcStat returns negative penetration ratings at the enemy's level.
        penetration = calc(penetrationStat, level, tier);
        assert(type(penetration) == "number" and penetration < 0,
            "Missing tier penetration data for " .. stat);
    end
    return cap - penetration,
        calc(prefix .. "PRatP", level, math.max(0, rating + penetration)),
        calc(prefix .. "PRatPCap", level);
end
