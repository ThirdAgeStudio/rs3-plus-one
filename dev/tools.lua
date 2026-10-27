-- dev/tools.lua: dev builds only
-- every request carries the session id, so testers sharing a server only reach their own fakes

local Log = require("log")
local Json = require("core/json")
local W = require("ui/widgets")
local GameReaper = require("game/reaper")
local Identity = require("dev/identity")

local Tools = {}

local CLIENT_KEY = "devClient"

function Tools.keepClient(net)
    local ok, saved = pcall(function() return PersistentDB:GetString(CLIENT_KEY) end)
    if ok and type(saved) == "string" and #saved == 16 then
        net.useClient(saved)
    else
        pcall(function() PersistentDB:SetString(CLIENT_KEY, net.client()) end)
    end
end

local NEX = 17

local ACCESS_COMMANDS = { "ppr plus-one-dev", "ppe plus-one-dev httpAccess" }

Tools.access = {
    commands = table.concat(ACCESS_COMMANDS, "; "),
    grant = function()
        for _, command in ipairs(ACCESS_COMMANDS) do
            local ok, err = pcall(ExecuteConsoleCommand, command)
            Log.log("action", "ran %s: %s", command, ok and "ok" or tostring(err))
        end
        local ok, allowed = pcall(function() return Plugin.HasPermission(PluginPermissions.httpAccess) end)
        Log.log("action", "httpAccess now %s", ok and tostring(allowed) or "unknown")
    end,
}

local function taskBoss()
    local task = GameReaper.task()
    return task and task.target or NEX
end

-- two along, since the server moves every third party one boss further
-- near the end of the 58 Reaper bosses it counts back instead
local function otherBoss()
    local own = taskBoss()
    return own > 55 and own - 5 or own + 2
end

-- a body can be a list, to send several requests from one button
local GROUPS = {
    { "As host", {
        { "Party: add applicant", "/dev/apply", function() return { count = 1 } end },
        { "Party: applicant leaves", "/dev/leave", function() return {} end },
        { "Reaper: ask to join", "/dev/pool/ask", function() return { boss = taskBoss() } end },
    } },
    { "As applicant", {
        { "Party: fill board", "/dev/board/fill", function() return {} end },
        { "Party: next change", "/dev/board/change", function() return {} end },
        { "Fakes accept me", "/dev/answer", function() return { accept = true } end },
        { "Fakes decline me", "/dev/answer", function() return { accept = false } end },
        { "Reaper: fill pool", "/dev/pool", function()
            return { { boss = taskBoss(), count = 1 }, { boss = otherBoss(), count = 3 } }
        end },
    } },
    { "Clean up", {
        { "Fakes go quiet", "/dev/quiet", function() return {} end },
        { "Clear the board", "/dev/clear", function() return {} end },
        { "Clear applicants", "/dev/clear/applicants", function() return {} end },
    } },
}

local CHANGE_TICKS = 8
local changing, ticks = false, 0
-- the server drops a token after 3 minutes without a poll
local KEEP_ALIVE_TICKS = 50
local keepingAlive, aliveTicks = false, 0

local function ask(net, path, body, quiet)
    body.client = net.client()
    local ok, err = pcall(function()
        local request = HTTPRequest.new(Plugin.urls.server, path)
        request:AddHeader("Content-Type", "application/json")
        request:Post(Json.encode(body), function(reply)
            if quiet then return end
            Log.log("action", "dev %s: %s %s", path, tostring(reply.responseCode), tostring(reply.data or ""):sub(1, 120))
        end)
    end)
    if not ok then Log.log("action", "dev %s failed: %s", path, tostring(err)) end
end

local function keepAwayAlive(net)
    if keepingAlive then return end
    keepingAlive = true
    Event.ServerLogic.Subscribe("plus-one-dev-alive", function()
        aliveTicks = aliveTicks + 1
        if aliveTicks % KEEP_ALIVE_TICKS ~= 0 then return end
        local tokens = Identity.awayTokens(net)
        if #tokens > 0 then ask(net, "/poll", { tokens = tokens }, true) end
    end)
end

local function stopChanges()
    if not changing then return end
    changing = false
    pcall(function() Event.ServerLogic.Unsubscribe("plus-one-dev-changes") end)
end

local function startChanges(net)
    changing, ticks = true, 0
    Event.ServerLogic.Subscribe("plus-one-dev-changes", function()
        ticks = ticks + 1
        if ticks % CHANGE_TICKS == 0 then ask(net, "/dev/board/change", {}) end
    end)
end

local function drawSection(layer, title, buttons, x, y, width, colour, note)
    W.label(layer, title, x, y, width, colour, "bold")
    if note then
        local noteX = x + W.textWidth(title) + 10
        W.label(layer, note, noteX, y, width - (noteX - x), W.MUTED)
    end
    y = y + 22
    local half = (width - 6) // 2
    for index, button in ipairs(buttons) do
        local left = x + ((index - 1) % 2) * (half + 6)
        local top = y + ((index - 1) // 2) * 36
        W.button(layer, W.escape(button.label), left, top, half, button.press, button.style or "plain", 30)
    end
    return y + ((#buttons + 1) // 2) * 36 + 6
end

function Tools.draw(layer, net, x, y, width, options)
    local top = y
    W.label(layer, "Dev tools", x, y, width, W.GOLD, "bold")
    y = y + 26

    local players = {}
    for _, choice in ipairs(Identity.choices(options.character)) do
        players[#players + 1] = {
            label = choice.label,
            style = Identity.active() == choice.key and "selected" or "plain",
            press = function()
                Identity.switch(net, choice.key)
                keepAwayAlive(net)
                options.onSwitch()
            end,
        }
    end
    y = drawSection(layer, "Players", players, x, y, width, W.SOFT, "who this client posts and applies as")

    W.label(layer, "Fakes", x, y, width, W.SOFT, "bold")
    W.label(layer, "server actions", x + W.textWidth("Fakes") + 10, y, width - W.textWidth("Fakes") - 10, W.MUTED)
    y = y + 24
    for _, group in ipairs(GROUPS) do
        local buttons = {}
        for _, button in ipairs(group[2]) do
            buttons[#buttons + 1] = { label = button[1], press = function()
                local body = button[3]()
                for _, each in ipairs(body[1] and body or { body }) do ask(net, button[2], each) end
            end }
        end
        if group[1] == "As applicant" then
            local reaperAt = #buttons + 1
            for index, button in ipairs(buttons) do
                if button.label:find("^Reaper:") then reaperAt = index break end
            end
            table.insert(buttons, reaperAt, { label = changing and "Party: stop changes" or "Party: change every 5 s", press = function()
                if changing then stopChanges() else startChanges(net) end
                options.onChange()
            end })
        end
        y = drawSection(layer, group[1], buttons, x, y, width, W.MUTED)
    end
    return y - top
end

function Tools.stop()
    stopChanges()
    if keepingAlive then
        keepingAlive = false
        pcall(function() Event.ServerLogic.Unsubscribe("plus-one-dev-alive") end)
    end
end

return Tools
