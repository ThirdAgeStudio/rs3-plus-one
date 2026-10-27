-- game/net.lua

local Json = require("core/json")
local Sync = require("core/sync")
local Pool = require("core/pool")
local Kills = require("game/kills")
local Log = require("log")

local Net = {}

local TICK_SECONDS = 0.6
local STORE_KEY = "listing"
local RETRY_SECONDS = 10
-- the server drops a token after 3 minutes without a poll
local BACKGROUND_SECONDS = 60

local sync = Sync.new()
local held = { key = STORE_KEY }
local inFlight = false
local pollNow = true
local waitSeconds = 0
local ticksSince = 0
local onChange = function() end
local wantsBoard = function() return false end
local wantsPool = function() return false end
local wantsUpdates = function() return false end
local boardInLastPoll, poolInLastPoll, openInLastPoll = false, false, false
local poolCopy, poolParties, stats = Pool.newCopy(), {}, {}
local statsSummary = ""
-- picked fresh at each load, so it says nothing about the player
local client = string.format("%08x%08x", math.random(0, 0xFFFFFFFF), math.random(0, 0xFFFFFFFF))

-- PersistentDB is shared by every character on the device, so for now so is the saved listing
local function save(target)
    pcall(function()
        PersistentDB:SetStructuredData(target.key, {
            mine = target.mine, applied = target.applied, pool = target.pool, server = sync.server,
        })
    end)
end

local function load(key)
    local ok, saved = pcall(function() return PersistentDB:GetStructuredData(key) end)
    if not ok or type(saved) ~= "table" then return { key = key } end
    local function token(entry) return type(entry) == "table" and entry.token and entry or nil end
    return {
        key = key, mine = token(saved.mine), applied = token(saved.applied), pool = token(saved.pool),
        server = type(saved.server) == "string" and saved.server or nil,
    }
end

local function send(path, body, done)
    local request = HTTPRequest.new(Plugin.urls.server, path)
    request:AddHeader("Content-Type", "application/json")
    request:Post(Json.encode(body), function(reply)
        local ok, answer = pcall(Json.decode, reply.data or "")
        if reply.successful and reply.responseCode == 200 and ok then
            done(answer, nil, reply.responseCode)
            return
        end
        local refusal = ok and type(answer) == "table" and answer or {}
        done(nil, refusal.error or reply.errorInfo or "no answer", reply.responseCode, refusal)
    end)
end

local function guarded(name, run)
    return function(...)
        local ok, err = pcall(run, ...)
        if not ok then Log.error("%s failed: %s", name, tostring(err)) end
    end
end

-- the plugin keeps tags as a set, the server takes a list
local function listingBody(listing)
    local body = {}
    for key, value in pairs(listing) do body[key] = value end
    body.tags = {}
    for tag in pairs(listing.tags or {}) do body.tags[#body.tags + 1] = tag end
    return body
end

-- after a restart each held token is restored on the new server under the same token
-- a restore that can't get through yet is tried again, and the slot is kept meanwhile
local RESTORE_WAIT_SECONDS, MAX_RESTORE_SECONDS = 4, 60
local restoring = {}

local function memberOf(party, name)
    for _, member in ipairs(party and party.members or {}) do
        if member.name == name then return member end
    end
end

local function restoreRequest(kind, entry)
    if kind == "mine" then
        local listing = listingBody(entry.listing)
        local members = {}
        for index, member in ipairs(listing.members or {}) do members[index] = { name = member.name, roles = member.roles } end
        return "/listings/restore", { token = entry.token, listing = {
            id = listing.id, host = listing.host, activity = listing.activity, size = listing.size, filled = listing.filled,
            needs = listing.needs, hostRoles = listing.hostRoles, members = members, world = listing.world, tags = listing.tags,
        } }
    end
    if kind == "applied" then
        if entry.status == "declined" then return nil end
        return "/applications/restore", {
            token = entry.token, id = entry.id, listing = entry.listing, applicant = entry.applicant, roles = entry.roles,
            kills = entry.kills, combat = entry.combat, status = entry.status,
        }
    end
    local party = entry.party or {}
    local me = memberOf(party, entry.name)
    local kills = me and me.kills or entry.kills
    if entry.leader then
        local members = {}
        for _, member in ipairs(party.members or {}) do
            if member ~= me then members[#members + 1] = { name = member.name, kills = member.kills } end
        end
        return "/pool/restore", { token = entry.token, members = members, party = {
            id = party.id, name = entry.name, kills = kills, boss = party.boss, world = party.world, size = party.size,
            open = party.open,
        } }
    end
    return "/pool/rejoin", {
        token = entry.token, party = party.id, name = entry.name, kills = kills, boss = party.boss or entry.boss,
        status = entry.asking and "asking" or "member", request = entry.asking and entry.request and entry.request.id or nil,
    }
end

local function drop(target, kind, why)
    Log.log("net", "%s dropped: %s", kind, tostring(why))
    restoring[kind] = nil
    target[kind] = nil
    save(target)
    onChange()
end

local function restore(kind)
    local target, entry = held, held[kind]
    if not entry then
        restoring[kind] = nil
        return
    end
    local state = restoring[kind] or { seconds = 0 }
    restoring[kind] = state
    if state.busy then return end
    local path, body = restoreRequest(kind, entry)
    if not path then return drop(target, kind, "declined before the restart") end
    state.busy, state.retryIn = true, nil
    Log.log("net", "restoring %s at %s", kind, path)
    send(path, body, guarded("restore " .. kind, function(answer, reason, code, refusal)
        state.busy = false
        code = code or 0
        if target[kind] ~= entry then return end
        -- 409: the token is already live, so it's there after all
        if reason == nil or code == 409 then
            restoring[kind] = nil
            if answer and answer.request then entry.request = answer.request end
            pollNow = true
            return
        end
        -- 404: what it attaches to isn't restored yet; 429: the server is busy
        if code == 404 or code == 429 or code == 0 or code >= 500 then
            local backOff = math.min(MAX_RESTORE_SECONDS, math.max(5, state.seconds * 2))
            state.seconds = code == 404 and RESTORE_WAIT_SECONDS or tonumber(refusal and refusal.retryAfter) or backOff
            state.retryIn = math.ceil(state.seconds / TICK_SECONDS)
            Log.log("net", "restore %s not through (%s), again in %d s", kind, tostring(reason), state.seconds)
            return
        end
        drop(target, kind, reason)
    end))
end

function Net.tokens(target)
    local tokens = {}
    for _, kind in ipairs({ "mine", "applied", "pool" }) do
        if target[kind] then tokens[#tokens + 1] = target[kind].token end
    end
    return tokens
end

local function handlePoll(answer, reason)
    inFlight = false
    if answer == nil then
        Log.log("net", "poll failed: %s", tostring(reason))
        waitSeconds = RETRY_SECONDS
        return
    end
    local restarted, boardChanged = Sync.apply(sync, answer)
    if restarted then poolCopy, poolParties = Pool.newCopy(), {} end
    if restarted then save(held) end
    local mineChanged = false
    if answer.stats then
        stats = answer.stats
        local summary = string.format("%s %s", tostring(stats.online), tostring(stats.poolPlayers))
        if summary ~= statsSummary then statsSummary, boardChanged = summary, true end
    end
    if answer.pool then
        if Pool.apply(poolCopy, answer.pool, answer.cursor) then
            poolParties, boardChanged = Pool.list(poolCopy), true
        end
    end
    local mine, applied, pool = held.mine, held.applied, held.pool
    for _, view in ipairs(answer.hosting or {}) do
        if mine and view.token == mine.token then
            local listing, summary = Sync.hosting(view)
            mine.listing = listing
            if summary ~= held.summary then held.summary, mineChanged = summary, true end
        end
    end
    if pool then
        local fresh, summary = Pool.mine(answer, pool.token)
        if fresh then
            fresh.name, fresh.kills, fresh.boss = pool.name, pool.kills, pool.boss
            held.pool = fresh
            if summary ~= held.poolSummary then held.poolSummary, mineChanged = summary, true end
        end
    end
    for _, view in ipairs(answer.applied or {}) do
        if applied and view.token == applied.token then
            local fresh, summary = Sync.applied(view)
            applied.status, applied.party = fresh.status, fresh.party
            if summary ~= held.appliedSummary then
                held.appliedSummary, mineChanged = summary, true
                save(held)
            end
        end
    end
    for _, token in ipairs(answer.unknown or {}) do
        for kind, entry in pairs({ mine = mine, applied = applied, pool = pool }) do
            if token == entry.token then
                if restarted then
                    restore(kind)
                elseif not restoring[kind] then
                    Log.log("net", "%s is gone from the server", kind)
                    held[kind], mineChanged = nil, true
                    save(held)
                end
            end
        end
    end
    -- a restart threw away the board, so poll again straight away from cursor 0
    -- a write answered while this poll was out has already asked for the next one
    if restarted then pollNow = true end
    waitSeconds = answer.interval or 30
    if boardChanged or mineChanged then
        Log.log("net", "poll changed: board %s, mine %s, pool sent %s", tostring(boardChanged), tostring(mineChanged),
            tostring(answer.pool ~= nil))
        onChange()
    end
end

-- fail early without httpAccess permission
local function poll()
    inFlight, pollNow, ticksSince = true, false, 0
    boardInLastPoll, poolInLastPoll, openInLastPoll = wantsBoard(), wantsPool(), wantsUpdates()
    local ok, err = pcall(send, "/poll", { tokens = Net.tokens(held), since = sync.cursor, poolSince = poolCopy.cursor, board = boardInLastPoll,
        pool = poolInLastPoll, client = client }, guarded("poll", handlePoll))
    if not ok then
        inFlight, waitSeconds = false, RETRY_SECONDS
        Log.log("net", "couldn't poll: %s", tostring(err))
    end
end

function Net.listings()
    local mine = held.mine
    return Sync.listings(sync, mine and mine.listing.id)
end

function Net.mine()
    return held.mine and held.mine.listing
end

-- the dev build plays several players from one client, each saved under its own slot
function Net.useSlot(slot)
    save(held)
    local away = held
    held = load(slot and (STORE_KEY .. ":" .. slot) or STORE_KEY)
    restoring = {}
    -- a slot saved under an earlier server is restored on its next poll, as after a reload
    if held.server then sync.server = held.server end
    pollNow = true
    return away
end

function Net.client()
    return client
end

-- the dev build keeps one id across reloads, so its fakes on the server stay reachable
function Net.useClient(id)
    client = id
end

local function write(path, body, done)
    send(path, body, guarded(path, function(_, reason)
        pollNow = true
        if done then done(reason) end
    end))
end

function Net.decide(applicationId, accept, done)
    local mine = held.mine
    if not mine then return done("no listing") end
    write("/applications/" .. applicationId .. (accept and "/accept" or "/decline"), { token = mine.token }, done)
end

function Net.stats()
    return stats
end

function Net.pool()
    return held.pool
end

function Net.poolParties()
    return poolParties
end

-- joining an open party is answered without the party, so the joiner fills in the one it saw on the list
local function poolAnswer(target, me, done, joined)
    return guarded("pool", function(answer, reason, code)
        if answer and answer.token then
            local party = answer.party or joined
            local request = answer.request
            target.pool = {
                token = answer.token, party = party, leader = party ~= nil, requests = {},
                asking = request ~= nil and request.status ~= "accepted", request = request,
                name = me.name, kills = me.kills, boss = me.boss,
            }
            target.poolSummary = nil
            save(target)
            pollNow = true
        end
        done(reason)
    end)
end

function Net.startPool(name, task, world, size, open, done)
    local me = { name = name, kills = { done = task.done, total = task.total }, boss = task.target }
    send("/pool/start", {
        name = name, kills = me.kills, boss = task.target, world = world, size = size, open = open,
    }, poolAnswer(held, me, done))
end

function Net.joinPool(partyId, name, task, done)
    local joined
    for _, party in ipairs(poolParties) do
        if party.id == partyId then joined = party end
    end
    local me = { name = name, kills = { done = task.done, total = task.total }, boss = task.target }
    send("/pool/parties/" .. partyId .. "/join", {
        name = name, kills = me.kills, boss = task.target,
    }, poolAnswer(held, me, done, joined))
end

function Net.answerPool(requestId, accept, done)
    local pool = held.pool
    if not pool then return done("not in the pool") end
    write("/pool/requests/" .. requestId .. (accept and "/accept" or "/decline"), { token = pool.token }, done)
end

function Net.setPoolOpen(open, done)
    local pool = held.pool
    if not pool then return done("not in the pool") end
    write("/pool/open", { token = pool.token, open = open }, done)
end

function Net.updatePoolKills(task)
    local pool = held.pool
    if not pool or not task then return end
    write("/pool/kills", { token = pool.token, kills = { done = task.done, total = task.total } })
end

-- 404: it had already gone, which is as good as released
local function release(target, kind, path, token, done)
    send(path, { token = token }, guarded(path, function(_, reason, code)
        if reason == nil or code == 404 then
            target[kind] = nil
            save(target)
            pollNow = true
        end
        if done then done(reason ~= nil and code ~= 404 and reason or nil) end
    end))
end

function Net.leavePool(done)
    if not held.pool then return done and done() end
    release(held, "pool", "/pool/leave", held.pool.token, done)
end

function Net.applied()
    return held.applied
end

function Net.apply(listing, name, roles, done)
    local target = held
    local body = {
        applicant = name, roles = roles,
        kills = Kills.of(listing.activity),
        combat = Kills.combat(),
    }
    send("/listings/" .. listing.id .. "/apply", body, guarded("apply", function(answer, reason)
        if answer then
            target.applied = {
                token = answer.token, id = answer.application.id, status = answer.application.status, roles = roles,
                listing = listing.id, activity = listing.activity, host = listing.host, world = listing.world,
                applicant = name, kills = body.kills, combat = body.combat,
            }
            save(target)
            pollNow = true
        end
        done(reason)
    end))
end

function Net.withdraw(done)
    local applied = held.applied
    if not applied then return done() end
    release(held, "applied", "/applications/" .. applied.id .. "/withdraw", applied.token, done)
end

function Net.post(fields, done)
    local target = held
    send("/listings", listingBody(fields), guarded("post", function(answer, reason)
        if answer then
            target.mine = { token = answer.token, listing = Sync.fromServer(answer.listing) }
            save(target)
            pollNow = true
        end
        done(answer and target.mine.listing, reason)
    end))
end

function Net.close(done)
    local mine = held.mine
    if not mine then return done() end
    release(held, "mine", "/listings/" .. mine.listing.id .. "/close", mine.token, done)
end

function Net.allowed()
    local ok, allowed = pcall(function() return Plugin.HasPermission(PluginPermissions.httpAccess) end)
    return ok and allowed == true
end

function Net.holding()
    return #Net.tokens(held) > 0
end

local function due()
    local open = wantsUpdates()
    if not open and not Net.holding() then return false end
    if pollNow then return true end
    if open and (not openInLastPoll or wantsBoard() ~= boardInLastPoll or wantsPool() ~= poolInLastPoll) then return true end
    local seconds = open and waitSeconds or math.max(BACKGROUND_SECONDS, waitSeconds)
    return ticksSince * TICK_SECONDS >= seconds
end

-- with the window closed, a player holding nothing isn't polled and one holding something only every minute
function Net.start(options)
    onChange, wantsUpdates = options.changed, options.open
    wantsBoard, wantsPool = options.board, options.pool
    held = load(STORE_KEY)
    -- remembered across reloads, so a listing saved before a server restart is sent again rather than dropped
    sync.server = held.server
    Event.ServerLogic.Subscribe("plus-one-net", guarded("tick", function()
        ticksSince = ticksSince + 1
        for kind, state in pairs(restoring) do
            if state.retryIn then
                state.retryIn = state.retryIn - 1
                if state.retryIn <= 0 then restore(kind) end
            end
        end
        if not inFlight and Net.allowed() and due() then poll() end
    end))
end

function Net.stop()
    pcall(function() Event.ServerLogic.Unsubscribe("plus-one-net") end)
end

return Net
