-- ui/reaper_tab.lua

local W = require("ui/widgets")
local Page = require("ui/page")
local Reaper = require("core/reaper")
local Pool = require("core/pool")
local GameReaper = require("game/reaper")

local ReaperTab = {}

local PAD = Page.PAD
local TASK_HEIGHT = 92
local PARTY_HEIGHT = 140
local REQUEST_HEIGHT = 70
local ROW_HEIGHT = 46
local TASK_FILL, TASK_EDGE = 0x1D2A22FF, 0x4E7A59FF

local form = nil

function ReaperTab.openStart(world)
    form = { world = world or "", size = 4, open = false }
    Page.open("pool_start")
end

function ReaperTab.problem(message)
    if form then form.problem = message end
end

local joinProblem = nil

function ReaperTab.joinProblem(message)
    joinProblem = message
end

-- size 0 is no limit, which draws no empty pips
local function emptyPips(party)
    return party.size == 0 and 0 or party.size - #(party.members or {})
end

local function drawTask(layer, width, y, task, pill, action)
    local cardWidth = width - PAD * 2
    W.panel(layer, PAD, y, cardWidth, TASK_HEIGHT, TASK_FILL, TASK_EDGE, Page.CARD_RADIUS)
    W.label(layer, "REAPER TASK", PAD + 12, y + 8, 160, W.GREEN)
    if pill then W.pill(layer, pill, PAD + cardWidth - 12, y + 7, W.GREEN, W.PANEL) end
    W.label(layer, task and Reaper.bossName(task.target) or "No Reaper task", PAD + 12, y + 24, cardWidth - 130,
        W.TEXT, "title")
    if task then
        W.label(layer, string.format("Kills %d/%d", task.done, task.total), PAD, y + 28, cardWidth - 12, W.SOFT, nil, true)
        local barWidth = cardWidth - 24
        W.roundedBox(layer, PAD + 12, y + 52, barWidth, 6, 0x2B3B30FF, 3)
        local done = task.total > 0 and barWidth * task.done // task.total or 0
        if done > 0 then W.roundedBox(layer, PAD + 12, y + 52, done, 6, W.GREEN, 3) end
    else
        W.label(layer, "Get a task from Death to join", PAD + 12, y + 48, cardWidth - 24, W.MUTED)
    end
    -- points belong to the player, not the task, so they show between tasks too
    local points = GameReaper.points()
    if points then W.label(layer, string.format("%d Reaper points", points), PAD + 12, y + 68, 150, W.MUTED) end
    if action then W.button(layer, action.label, PAD + cardWidth - 12 - 120, y + 62, 120, action.press, "green", 24) end
    return y + TASK_HEIGHT
end

local function drawParty(layer, width, y, pool)
    local cardWidth = width - PAD * 2
    local party = pool.party
    local members = party.members or {}
    W.panel(layer, PAD, y, cardWidth, PARTY_HEIGHT, W.CARD, TASK_EDGE, Page.CARD_RADIUS)
    W.label(layer, "Your party", PAD + 12, y + 8, 120, W.GREEN, "bold")
    local count = party.size == 0 and string.format("%d  W%d", #members, party.world or 0)
        or string.format("%d/%d  W%d", #members, party.size, party.world or 0)
    W.label(layer, count, PAD, y + 9, cardWidth - 12, W.SOFT, nil, true)
    local spots = #members + emptyPips(party)
    W.pips(layer, PAD + cardWidth - 12 - W.textWidth(count) - 8 - 14 * spots + 3, y + 12, #members, emptyPips(party))
    local names = {}
    for index, member in ipairs(members) do names[index] = W.escape(member.name) end
    W.label(layer, table.concat(names, ", "), PAD + 12, y + 30, cardWidth - 24, W.TEXT)
    W.label(layer, "kills " .. Pool.killsLine(members), PAD + 12, y + 47, cardWidth - 24, W.MUTED)

    local asked = pool.requests and pool.requests[1]
    if pool.leader and asked then
        W.roundedBox(layer, PAD + 8, y + 66, cardWidth - 16, 32, 0x26352BFF, 4)
        local more = #pool.requests > 1 and string.format(" +%d", #pool.requests - 1) or ""
        W.label(layer, W.escape(asked.name) .. more, PAD + 14, y + 68, cardWidth - 170, W.TEXT, "bold")
        if asked.kills and asked.kills.total > 0 then
            W.label(layer, string.format("%d/%d", asked.kills.done, asked.kills.total), PAD + 14, y + 83, 80, W.MUTED)
        end
        Page.sendButton(layer, "Accept", "answer:" .. asked.id, PAD + cardWidth - 150, y + 70, 66,
            function() Page.act("pool_accept", asked.id) end,
            "green", 24)
        Page.sendButton(layer, "Decline", "answer:" .. asked.id, PAD + cardWidth - 80, y + 70, 66,
            function() Page.act("pool_decline", asked.id) end,
            "plain", 24)
    end
    if pool.leader then
        W.label(layer, "Open party", PAD + 12, y + 110, 100, W.SOFT)
        W.switch(layer, PAD + 104, y + 110, party.open,
            not Page.waiting("pool_open") and function() Page.act("pool_open", not party.open) end or nil)
    end
    Page.sendButton(layer, "Leave", "pool_leave", PAD + cardWidth - 12 - 76, y + 106, 76, function() Page.act("pool_leave") end,
        "plain", 26)
    return y + PARTY_HEIGHT
end

local function drawRequest(layer, width, y, pool)
    local cardWidth = width - PAD * 2
    local party = pool.party
    local declined = pool.request and pool.request.status == "declined"
    W.panel(layer, PAD, y, cardWidth, REQUEST_HEIGHT, W.CARD, 0xC9A24CFF, Page.CARD_RADIUS)
    W.label(layer, "ASKED TO JOIN", PAD + 12, y + 8, 160, W.GOLD)
    W.pill(layer, declined and "Declined" or "Pending", PAD + cardWidth - 12, y + 7,
        declined and 0x5A2A2AFF or W.BAR_EDGE, W.SOFT)
    if party then
        W.label(layer, Reaper.bossName(party.boss) .. string.format("  W%d", party.world or 0), PAD + 12, y + 30,
            cardWidth - 130, W.TEXT, "bold")
        W.pips(layer, PAD + 12, y + 52, #(party.members or {}), emptyPips(party))
    end
    Page.sendButton(layer, declined and "Dismiss" or "Withdraw", "pool_leave", PAD + cardWidth - 12 - 84, y + 36, 84,
        function() Page.act("pool_leave") end, "plain", 26)
    return y + REQUEST_HEIGHT
end

local function drawRow(layer, width, y, party, canJoin)
    local members = party.members or {}
    canJoin = canJoin and (party.size == 0 or #members < party.size) and not Page.waiting("pool_join")
    local boss = Reaper.bossName(party.boss)
    W.label(layer, boss, PAD + 2, y + 5, 130, W.TEXT, "bold")
    W.pips(layer, PAD + 2 + math.min(130, W.textWidth(boss)) + 8, y + 9, #members, emptyPips(party))
    W.label(layer, Pool.killsLine(members), PAD + 2, y + 24, width - PAD * 2 - 140, W.MUTED)
    W.stat(layer, "WORLD", W.world(party.world), width - PAD - 2 - 56 - 58, y + 6, 54)
    W.button(layer, "Join", width - PAD - 2 - 56, y + 9, 56,
        canJoin and function()
            joinProblem = nil
            Page.act("pool_join", party.id)
        end or nil, canJoin and "green" or "off", 28)
    W.box(layer, PAD, y + ROW_HEIGHT - 1, width - PAD * 2, 1, W.ROW_LINE)
end

local function drawLists(layer, width, height, y, same, other, canJoin)
    for _, section in ipairs({ { "Same task", same }, { "Other bosses", other } }) do
        local title, parties = section[1], section[2]
        if y + 22 + ROW_HEIGHT > height then return end
        W.label(layer, title, PAD, y, width - PAD * 2, W.GOLD, "bold")
        y = y + 22
        if #parties == 0 then
            W.label(layer, "No parties yet", PAD + 2, y, width - PAD * 2, W.MUTED)
            y = y + 24
        end
        for index, party in ipairs(parties) do
            if y + ROW_HEIGHT > height then
                W.label(layer, string.format("+%d more", #parties - index + 1), PAD + 2, y, width - PAD * 2, W.MUTED)
                y = y + 20
                break
            end
            drawRow(layer, width, y, party, canJoin)
            y = y + ROW_HEIGHT
        end
        y = y + 8
    end
end

local function drawStart(layer, width, height, task)
    local cardWidth = width - PAD * 2
    local function change(apply)
        return function()
            apply()
            form.problem = nil
            Page.act("redraw")
        end
    end
    local y = drawTask(layer, width, Page.backBar(layer, width, "Start a party"), task) + 14

    W.label(layer, "World", PAD, y + 7, 100, W.GOLD, "bold")
    W.input(layer, form.world, PAD + 100, y, 80, function(text) form.world = text end, 30)
    y = y + 42
    -- the stepper sits out while there's no limit
    W.label(layer, "Party limit", PAD, y + 5, 100, W.GOLD, "bold")
    local limited = form.size > 0
    W.stepper(layer, PAD + 100, y, limited and form.size or "-",
        limited and form.size > 2 and change(function() form.size = form.size - 1 end) or nil,
        limited and form.size < 10 and change(function() form.size = form.size + 1 end) or nil)
    W.button(layer, "No limit", PAD + 192, y, 80, change(function() form.size = limited and 0 or 4 end),
        limited and "plain" or "selected", 26)
    y = y + 40
    W.label(layer, "Open party", PAD, y + 5, 100, W.GOLD, "bold")
    W.switch(layer, PAD + 100, y + 5, form.open, change(function() form.open = not form.open end))

    Page.problemLine(layer, width, height, form.problem)
    Page.sendButton(layer, "Start party", "pool_start", PAD, height - PAD - 40, cardWidth, function()
        Page.act("pool_start", { world = math.tointeger(tonumber(form.world)), size = form.size, open = form.open })
    end, "green", 40, "Starting...")
end

function ReaperTab.draw(layer, width, height, state)
    local task = GameReaper.task()
    local pool = state.pool
    if Page.top() == "pool_start" then
        if task and not Page.busy(state) and form then return drawStart(layer, width, height, task) end
        Page.clear()
    end
    local start = (task and not Page.busy(state)) and { label = "Start a party", press = function() Page.act("pool_start_open") end }
        or nil
    local inParty = pool and not pool.asking and pool.party ~= nil
    local y = drawTask(layer, width, PAD, task, inParty and "In the pool" or nil, start) + 10
    if inParty then
        y = drawParty(layer, width, y, pool) + 10
    elseif pool and pool.asking then
        y = drawRequest(layer, width, y, pool) + 10
    end
    if pool then joinProblem = nil end
    if joinProblem then
        W.label(layer, W.escape(joinProblem), PAD, y, width - PAD * 2, W.PROBLEM)
        y = y + 24
    end
    local same, other = Pool.sections(state.poolParties, task and task.target, inParty and pool.party.id or nil)
    drawLists(layer, width, height, y, same, other, task ~= nil and not Page.busy(state))
end

function ReaperTab.footer(state)
    local pooled = state.poolPlayers
    if not pooled or pooled == 0 then return nil end
    local task = GameReaper.task()
    local onBoss = task and Pool.onBoss(state.poolParties, task.target) or 0
    return onBoss > 0 and string.format("%d looking, %d on your boss", pooled, onBoss)
        or string.format("%d looking", pooled)
end

function ReaperTab.fullPage()
    return Page.top() == "pool_start"
end

return ReaperTab
