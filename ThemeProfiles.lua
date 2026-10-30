StatCapsThemeProfiles = {};
StatCapsThemeProfiles.Races = { "Gondorian", "Man", "Elf", "Dwarf", "Hobbit",
    "Beorning", "HighElf", "StoutAxe", "RiverHobbit" };
StatCapsThemeProfiles.Classes = { "Beorning", "Brawler", "Burglar", "Captain",
    "Champion", "Guardian", "Hunter", "LoreMaster", "Mariner", "Minstrel", "RuneKeeper", "Warden" };

local raceColours = {
    Gondorian = { 153, 126, 73 }, Man = { 176, 147, 91 },
    Elf = { 151, 185, 157 }, Dwarf = { 191, 142, 83 },
    Hobbit = { 175, 153, 91 }, Beorning = { 183, 142, 92 },
    HighElf = { 176, 184, 218 }, StoutAxe = { 198, 124, 81 },
    RiverHobbit = { 127, 184, 178 }
};
local function contains(list, value)
    for _, name in ipairs(list) do if (name == value) then return true; end end
    return false;
end
local function detect(player, method, enum, names, calcName, calc)
    local ok, id = pcall(function() return player[method](player); end);
    if (not ok or id == nil) then return nil, tostring(id); end
    for _, name in ipairs(names) do
        if (enum and enum[name] ~= nil and enum[name] == id) then return name; end
    end
    if (type(calc) == "function") then
        local read, name = pcall(calc, calcName, id);
        if (read and contains(names, name)) then return name; end
    end
    return nil, tostring(id);
end

-- Race design and class badge are independent; each is a manual choice or detected (Automatic).
function StatCapsThemeProfiles.Resolve(config, player, gameplay, calc)
    config = type(config) == "table" and config or {};
    local race = contains(StatCapsThemeProfiles.Races, config.race) and config.race or nil;
    local class = contains(StatCapsThemeProfiles.Classes, config.class) and config.class or nil;
    local problems = {};
    if (not race) then
        race = detect(player, "GetRace", gameplay.Race, StatCapsThemeProfiles.Races, "RaceName", calc);
        if (not race) then problems[#problems + 1] = "Race detection unavailable; using Gondorian."; end
    end
    if (not class) then
        class = detect(player, "GetClass", gameplay.Class, StatCapsThemeProfiles.Classes, "ClassName", calc);
        if (not class) then problems[#problems + 1] = "Class detection unavailable; no class accent applied."; end
    end
    race = race or "Gondorian";
    return { race = race, class = class, colour = raceColours[race],
        folder = race ~= "Gondorian" and ("races/" .. race .. "/") or "",
        warning = #problems > 0 and table.concat(problems, "\n") or nil };
end
