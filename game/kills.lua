-- game/kills.lua

local Log = require("log")

local Kills = {}

local VARS = {
    vorago = "BSLAY_KILLS_VORAGO",
    solak = "BSLAY_KILLS_SOLAK",
    croesus = "BSLAY_KILLS_CROESUS",
}

local missing = {}

function Kills.of(activity)
    local name = VARS[activity]
    if name == nil then return 0 end
    local ok, value = pcall(function() return var.VarPlayer[name].value end)
    if ok and type(value) == "number" then return value end
    if not missing[name] then
        missing[name] = true
        Log.log("net", "no kill count var %s for %s", name, activity)
    end
    return 0
end

function Kills.combat()
    local ok, level = pcall(function() return Player.GetCombatLevel() end)
    return ok and type(level) == "number" and level or 0
end

return Kills
