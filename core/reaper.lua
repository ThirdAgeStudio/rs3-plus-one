-- core/reaper.lua: the Reaper task's boss, from BSLAY_TARGET's number
-- the numbers and names are the game's own: each Reaper boss has a struct in the game cache whose
-- param 1346 is its BSLAY_TARGET number and param 1348 its name (decoded with rs3cache from the
-- live cache, 2026-10-26; Nex as 17 and Araxxi as 1 checked against tasks in game)
-- a boss added to Reaper later reads as "Boss #<n>" until this table is updated

local Reaper = {}

local BOSSES = {
    [1] = "Araxxi",
    [2] = "The Barrows Brothers",
    [3] = "The Barrows: Rise of the Six",
    [4] = "Chaos Elemental",
    [5] = "Commander Zilyana",
    [6] = "Corporeal Beast",
    [7] = "Dagannoth Kings",
    [8] = "General Graardor",
    [9] = "Giant Mole",
    [10] = "Har-Aken",
    [11] = "Kalphite King",
    [12] = "Kalphite Queen",
    [13] = "King Black Dragon",
    [14] = "Kree'arra",
    [15] = "K'ril Tsutsaroth",
    [16] = "Legiones",
    [17] = "Nex",
    [18] = "Queen Black Dragon",
    [19] = "TzTok-Jad",
    [20] = "Vorago",
    [21] = "Beastmaster Durzag",
    [22] = "Yakamaru",
    [23] = "The Twin Furies",
    [24] = "Vindicta & Gorvek",
    [25] = "Gregorovic",
    [26] = "Helwyr",
    [27] = "Telos",
    [28] = "Nex, Angel of Death",
    [29] = "The Magister",
    [30] = "Solak, Guardian of the Grove",
    [31] = "The Sanctum Guardian",
    [32] = "Masuta the Ascended",
    [33] = "Seiryu the Azure Serpent",
    [34] = "Astellarn",
    [35] = "Verak Lith",
    [36] = "Black Stone Dragon",
    [37] = "Crassian Leviathan",
    [38] = "Taraket the Necromancer",
    [39] = "The Ambassador",
    [40] = "Raksha, the Shadow Colossus",
    [41] = "Rex Matriarchs",
    [42] = "Kerapac, the bound",
    [43] = "Arch-Glacor",
    [44] = "Croesus",
    [45] = "TzKal-Zuk",
    [46] = "Zamorak, Lord of Chaos",
    [47] = "Hermod, the Spirit of War",
    [48] = "Rasial, the First Necromancer",
    [49] = "Zemouregal & Vorkath",
    [50] = "Vermyx, Brood Mother",
    [51] = "Kezalam, the Wanderer",
    [52] = "Nakatra, Devourer Eternal",
    [53] = "The Gate of Elidinis",
    [54] = "Amascut, the Devourer",
    [55] = "Flesh-hatcher Mhekarnahz",
    [56] = "Ivar, King of Bones",
    [57] = "Silverquill, the Dreadhog",
    [58] = "The Ghrazi Blood Knights",
}

function Reaper.bossName(target)
    if target == nil then return nil end
    return BOSSES[target] or string.format("Boss #%d", target)
end

return Reaper
