-- game/reaper.lua

local GameReaper = {}

local function read(name)
    local ok, value = pcall(function() return var.VarPlayer[name].value end)
    if ok and type(value) == "number" then return value end
    return nil
end

-- 0 means between tasks
function GameReaper.task()
    local target = read("BSLAY_TARGET")
    if target == nil or target <= 0 then return nil end
    local left, total = read("BSLAY_KILLS_LEFT") or 0, read("BSLAY_KILLS_LEFT_ORIGINAL") or 0
    return { target = target, done = math.max(0, total - left), total = total }
end

-- false while the game can't be read yet, such as at login, as opposed to there being no task
function GameReaper.readable()
    return read("BSLAY_TARGET") ~= nil
end

function GameReaper.points()
    return read("BSLAY_POINTS")
end

return GameReaper
