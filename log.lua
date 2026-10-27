-- log.lua
-- logs only reach my own Dev Tools plugin

local Log = {}

local sink = nil

function Log.use(devTools)
    sink = devTools and devTools.logger("Plus One") or nil
end

function Log.log(...)
    if sink then sink.log(...) end
end

-- errors print to the console for everyone, once each, since a broken handler can fail every tick
local reported = {}

function Log.error(fmt, ...)
    local line = string.format(fmt, ...)
    if sink then sink.log(line) end
    if reported[line] then return end
    reported[line] = true
    print("Plus One: " .. line)
end

function Log.enable(...)
    if sink then sink.enable(...) end
end

return Log
