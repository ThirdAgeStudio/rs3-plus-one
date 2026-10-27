-- main.lua

local Log = require("log")
local Status = require("core/status")
local Window = require("ui/window")
local Compact = require("ui/compact")
local Full = require("ui/full")
local Page = require("ui/page")
local Apply = require("ui/apply")
local Post = require("ui/post")
local ReaperTab = require("ui/reaper_tab")
local W = require("ui/widgets")
local Net = require("game/net")
local GameReaper = require("game/reaper")

local function useDevTools(enabled)
    Log.use(enabled and DevTools or nil)
    Log.enable("window", "action", "net")
end
useDevTools(true)

-- dev/ is only in the dev build
-- the client's require returns nil for a missing file rather than raising, so the result is checked as well
local function optional(name)
    local ok, module = pcall(require, name)
    return ok and module or nil
end

local Identity = optional("dev/identity")
local Tools = optional("dev/tools")
if Tools then Tools.keepClient(Net) end

local state = { listings = {}, poolParties = {}, stats = {} }
local confirmingClose = false
local window, tabHost, tabRoot = nil, nil, nil
local drawTab

local playerName

local function readNet()
    state.playerName = playerName()
    state.listing, state.listings, state.application = Net.mine(), Net.listings(), Net.applied()
    state.pool, state.poolParties, state.stats = Net.pool(), Net.poolParties(), Net.stats()
    state.poolPlayers = state.stats.poolPlayers
    state.notice = Page.notice()
end

local function redraw()
    readNet()
    if window:isOpen() then window:redraw() end
    drawTab()
end

local function characterName()
    local ok, name = pcall(function() return Player.GetEntity().displayName end)
    return ok and name or nil
end

playerName = function()
    local other = Identity and Identity.name()
    if other then return other end
    return characterName()
end

-- the result of a request arrives with the next poll, so a reply only needs logging if refused
local function refusedThen(what, after)
    return function(reason)
        if reason then Log.log("action", "%s refused: %s", what, reason) end
        if after then after(reason) elseif reason then Page.setNotice(reason) end
        redraw()
    end
end

-- the key's button shows it's waiting until the answer, and a second press sends nothing
local function request(key, call, onAnswer)
    if Page.waiting(key) then return end
    Page.setWaiting(key, true)
    local ok, err = pcall(call, function(...)
        Page.setWaiting(key, false)
        onAnswer(...)
    end)
    if not ok then
        Page.setWaiting(key, false)
        error(err, 0)
    end
end

local WORLD_KEY = "world"

local function savedWorld()
    local ok, world = pcall(function() return PersistentDB:GetString(WORLD_KEY) end)
    return ok and world or ""
end

local function saveWorld(world)
    pcall(function() PersistentDB:SetString(WORLD_KEY, world) end)
end

local function openFull(tab)
    if tab then Full.showTab(tab) end
    if window.view ~= "full" then window:setView("full") end
    window:open()
end

local ACTIONS = {
    accept = function(id)
        request("decide:" .. id, function(answered) Net.decide(id, true, answered) end, refusedThen("accept"))
    end,
    decline = function(id)
        request("decide:" .. id, function(answered) Net.decide(id, false, answered) end, refusedThen("decline"))
    end,
    close_listing = function() request("close_listing", Net.close, refusedThen("close")) end,
    post = function()
        if not Page.busy(state) then Post.open(savedWorld()) end
    end,
    post_send = function(fields)
        fields.host = playerName()
        request("post_send", function(answered) Net.post(fields, answered) end, function(listing, reason)
            Log.log("action", "post %s", listing and ("made " .. listing.id) or ("refused: " .. tostring(reason)))
            if listing then
                if fields.world then saveWorld(tostring(fields.world)) end
                Page.back()
            else
                Post.problem(reason)
            end
            redraw()
        end)
    end,
    open_applications = function() Page.open("applications") end,
    open_apply = function(listingId) Apply.open(listingId) end,
    apply = function(form)
        request("apply", function(answered) Net.apply(form.listing, playerName(), form.roles, answered) end,
            refusedThen("apply", function(reason)
                if reason then Apply.problem(reason) else Page.back() end
            end))
    end,
    withdraw = function() request("withdraw", Net.withdraw, refusedThen("withdraw")) end,
    dismiss = function() request("withdraw", Net.withdraw, refusedThen("dismiss")) end,
    pool_start_open = function()
        ReaperTab.openStart(savedWorld())
    end,
    pool_start = function(form)
        local task = GameReaper.task()
        if not task then return end
        request("pool_start", function(answered)
            Net.startPool(playerName(), task, form.world, form.size, form.open, answered)
        end, refusedThen("start party", function(reason)
            if reason then
                ReaperTab.problem(reason)
                return
            end
            saveWorld(form.world)
            Page.back()
        end))
    end,
    pool_join = function(partyId)
        local task = GameReaper.task()
        if not task then return end
        request("pool_join", function(answered) Net.joinPool(partyId, playerName(), task, answered) end,
            refusedThen("join", ReaperTab.joinProblem))
    end,
    pool_accept = function(requestId)
        request("answer:" .. requestId, function(answered) Net.answerPool(requestId, true, answered) end,
            refusedThen("accept"))
    end,
    pool_decline = function(requestId)
        request("answer:" .. requestId, function(answered) Net.answerPool(requestId, false, answered) end,
            refusedThen("decline"))
    end,
    pool_open = function(open)
        request("pool_open", function(answered) Net.setPoolOpen(open, answered) end, refusedThen("open"))
    end,
    pool_leave = function() request("pool_leave", Net.leavePool, refusedThen("leave")) end,
    back = function() Page.back() end,
    browse = function() openFull("parties") end,
    join_pool = function() openFull("reaper") end,
}

local function act(name, data)
    Log.log("action", "%s %s", name, tostring(data or ""))
    if name ~= "redraw" then Page.setNotice(nil) end
    local run = ACTIONS[name]
    if run then
        local ok, err = pcall(run, data)
        if not ok then Log.error("%s failed: %s", name, tostring(err)) end
    end
    redraw()
end

local function closeNow()
    confirmingClose = false
    window:close()
    drawTab()
end

window = Window.new({ full = { 360, 640 }, compact = { 260, 170 } }, function(view, layer, width, height)
    if confirmingClose then
        Page.closeWarning(layer, width, function()
            confirmingClose = false
            redraw()
        end, closeNow)
    elseif not Net.allowed() then
        Page.needsAccess(layer, width, Tools and Tools.access)
    elseif view == "full" then
        Full.draw(layer, width, state, height, act)
    else
        Compact.draw(layer, width, Status.compact(state), act)
    end
end)
window.onClosed = function() drawTab() end
window.confirmClose = function()
    if confirmingClose or not Net.holding() then return false end
    confirmingClose = true
    redraw()
    return true
end

-- the game only builds the tab while it's open, so a failed draw drops it
drawTab = function()
    if tabHost == nil then return end
    local ok, err = pcall(function()
        if tabRoot == nil then
            tabRoot = ui.Layer.new(tabHost)
            tabRoot:SetSize(tabHost.width, tabHost.height)
        end
        tabRoot:DeleteAll()
        W.button(tabRoot, window:isOpen() and "Close window" or "Open window", 10, 10, 120, function()
            if window:isOpen() then window:requestClose() else window:open() end
            drawTab()
        end, "gold", 30)
        if Tools then
            Tools.draw(tabRoot, Net, 10, 52, tabHost.width - 20, {
                character = characterName(),
                onChange = drawTab,
                onSwitch = function()
                    local other = Identity.name()
                    window:setTitle(other and "Plus One (as " .. other .. ")" or "Plus One")
                    Log.log("action", "now playing as %s", Identity.active())
                    redraw()
                end,
            })
        end
    end)
    if not ok then
        Log.error("tab draw failed: %s", tostring(err))
        tabHost, tabRoot = nil, nil
    end
end

-- the task is read every few ticks rather than on each var change, since in combat the game sends
-- many var changes a tick and the task changes once a kill
local REAPER_CHECK_TICKS = 5

local function reaperShown()
    local task = GameReaper.task()
    return string.format("%s %s %s %s", task and task.target, task and task.done, task and task.total,
        GameReaper.points())
end
local lastReaper = reaperShown()
local leaving = false

local function poolBoss()
    local pool = Net.pool()
    return pool and pool.party and pool.party.boss
end

-- the pool groups players by task, so a new task takes the player out of it, retried each check until it goes through
local function leaveIfTaskChanged(task)
    local boss = poolBoss()
    if leaving or boss == nil or (task and task.target == boss) or not GameReaper.readable() then return end
    Log.log("action", "Reaper task is now %s, leaving the pool for boss %s", tostring(task and task.target), tostring(boss))
    leaving = true
    Net.leavePool(refusedThen("leave on task change", function() leaving = false end))
end

local reaperTicks = 0
Event.ServerLogic.Subscribe("plus-one-reaper", function()
    reaperTicks = reaperTicks + 1
    if reaperTicks % REAPER_CHECK_TICKS ~= 0 then return end
    local ok, err = pcall(function()
        local task = GameReaper.task()
        leaveIfTaskChanged(task)
        local shown = reaperShown()
        if shown == lastReaper then return end
        Log.log("action", "Reaper task now %s", shown)
        lastReaper = shown
        if task and task.target == poolBoss() then Net.updatePoolKills(task) end
        redraw()
    end)
    if not ok then Log.error("Reaper check failed: %s", tostring(err)) end
end)

Event.ContentLayerReady.Subscribe("plus-one-tab", function(event)
    local ok, err = pcall(function()
        tabHost, tabRoot = event.component, nil
        Log.log("window", "tab opened, %dx%d", tabHost.width, tabHost.height)
        drawTab()
    end)
    if not ok then Log.error("tab failed: %s", tostring(err)) end
end)

local function showing(tab)
    return window:isOpen() and window.view == "full" and Full.tab() == tab
end
local TYPING_PAGES = { post = true, pool_start = true }
local function redrawAfterPoll()
    if window.view == "full" and TYPING_PAGES[Page.top()] then return end
    readNet()
    if window:isOpen() and window.view == "full" and Full.refresh() then
        drawTab()
        return
    end
    redraw()
end
Event.OptionalPermissionChanged.Subscribe("plus-one-permission", function() redraw() end)
-- Dev Tools can be turned on after Plus One, or reloaded under it
Event.OptionalDependencyChanged.Subscribe("plus-one-dev-tools", function(event)
    pcall(useDevTools, event.enabled)
end)
Net.start({
    changed = redrawAfterPoll,
    open = function() return window:isOpen() end,
    board = function() return showing("parties") end,
    pool = function() return showing("reaper") end,
})

function PluginShutdown()
    Net.stop()
    if Tools then Tools.stop() end
    Event.ContentLayerReady.Unsubscribe("plus-one-tab")
    Event.ServerLogic.Unsubscribe("plus-one-reaper")
    Event.OptionalPermissionChanged.Unsubscribe("plus-one-permission")
    Event.OptionalDependencyChanged.Unsubscribe("plus-one-dev-tools")
    window:close()
    if tabRoot ~= nil then pcall(function() tabRoot:Destroy() end) end
end
