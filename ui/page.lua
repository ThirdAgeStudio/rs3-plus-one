-- ui/page.lua

local W = require("ui/widgets")
local Activities = require("core/activities")
local Listing = require("core/listing")

local Page = {}

Page.PAD = 12
Page.CARD_RADIUS = 6
Page.PAGER_HEIGHT = 30

local stack = {}
local run = function() end

function Page.setAction(fn)
    run = fn
end

function Page.act(name, data)
    run(name, data)
end

function Page.open(name, data)
    stack[#stack + 1] = { name = name, data = data }
end

function Page.back()
    stack[#stack] = nil
end

function Page.clear()
    stack = {}
end

function Page.top()
    local page = stack[#stack]
    return page and page.name, page and page.data
end

function Page.activityName(key)
    return Activities.name(key) or "Unknown"
end

function Page.problemLine(layer, width, height, problem)
    if problem then W.label(layer, W.escape(problem), Page.PAD, height - Page.PAD - 62, width - Page.PAD * 2, W.PROBLEM) end
end

-- one party at a time: hosting, applying, or a place in the Reaper pool
function Page.busy(state)
    return state.listing ~= nil or state.application ~= nil or state.pool ~= nil
end

local notice = nil
-- requests still waiting on the server, so their buttons can't send them twice
local waiting = {}

function Page.setWaiting(key, on)
    waiting[key] = on or nil
end

function Page.waiting(key)
    return waiting[key] ~= nil
end

function Page.sendButton(layer, label, key, x, y, width, press, style, height, waitingLabel)
    if Page.waiting(key) then return W.button(layer, waitingLabel or "...", x, y, width, nil, "off", height) end
    return W.button(layer, label, x, y, width, press, style, height)
end

function Page.setNotice(message)
    notice = message
end

function Page.notice()
    return notice
end

function Page.findListing(state, id)
    for _, listing in ipairs(state.listings or {}) do
        if listing.id == id then return listing end
    end
    return nil
end

function Page.backBar(layer, width, title)
    W.button(layer, "<lt> Back", Page.PAD, Page.PAD, 70, function() Page.act("back") end, "plain", 30)
    W.label(layer, title, Page.PAD + 80, Page.PAD + 6, width - Page.PAD * 2 - 80, W.TEXT, "bold")
    return Page.PAD + 40
end

function Page.needsAccess(layer, width, access)
    local fullWidth = width - Page.PAD * 2
    W.label(layer, "Needs HTTP access to find parties", Page.PAD, Page.PAD + 30, fullWidth, W.GOLD, "bold")
    W.label(layer, "Turn it on in Plus One's permissions", Page.PAD, Page.PAD + 54, fullWidth, W.TEXT)
    if not access then return end
    W.label(layer, "Dev build only", Page.PAD, Page.PAD + 86, fullWidth, W.MUTED)
    W.button(layer, "Grant HTTP access", Page.PAD, Page.PAD + 106, fullWidth, access.grant, "gold", 30)
    W.label(layer, "or paste this in the console", Page.PAD, Page.PAD + 146, fullWidth, W.MUTED)
    W.input(layer, access.commands, Page.PAD, Page.PAD + 166, fullWidth, nil, 30)
end

function Page.closeWarning(layer, width, keepOpen, close)
    local fullWidth = width - Page.PAD * 2
    local half = (fullWidth - 8) // 2
    W.label(layer, "Close Plus One?", Page.PAD, Page.PAD + 4, fullWidth, W.GOLD, "bold")
    W.label(layer, "Updates slow to once a minute", Page.PAD, Page.PAD + 28, fullWidth, W.TEXT)
    W.label(layer, "until you open it again", Page.PAD, Page.PAD + 46, fullWidth, W.TEXT)
    W.button(layer, "Keep open", Page.PAD, Page.PAD + 76, half, keepOpen, "gold", 30)
    W.button(layer, "Close", Page.PAD + half + 8, Page.PAD + 76, half, close, "plain", 30)
end

function Page.header(layer, width, y, text, right)
    W.label(layer, text, Page.PAD, y, width - Page.PAD * 2, W.GOLD, "bold")
    if right then W.label(layer, right, Page.PAD, y + 1, width - Page.PAD * 2, W.MUTED, nil, true) end
end

function Page.pager(layer, width, y, page, pages, turn)
    -- the game reads "<" as a formatting tag, and "<lt>" is how it shows one
    if page > 1 then W.button(layer, "<lt>", width / 2 - 70, y, 30, function() turn(-1) end, "plain", 24) end
    W.label(layer, string.format("%d / %d", page, pages), width / 2 - 30, y + 3, 60, W.MUTED)
    if page < pages then W.button(layer, ">", width / 2 + 40, y, 30, function() turn(1) end, "plain", 24) end
end

function Page.roleChips(listing)
    local filled, needed = {}, {}
    for _, role in ipairs(Listing.grouped(Listing.filledRoles(listing))) do filled[#filled + 1] = { text = role, kind = "filled" } end
    for _, role in ipairs(Listing.grouped(listing.needs or {})) do needed[#needed + 1] = { text = role, kind = "needed" } end
    return filled, needed
end

-- roles as buttons, three to a row, that toggle in and out of chosen (a set); returns the y below them
function Page.roleToggles(layer, width, y, roles, chosen, onToggle)
    if #roles == 0 then return y end
    local perRow = math.min(#roles, 3)
    local roleWidth = math.floor((width - Page.PAD * 2 - 6 * (perRow - 1)) / perRow)
    for index, role in ipairs(roles) do
        local column, row = (index - 1) % perRow, (index - 1) // perRow
        W.button(layer, W.escape(role), Page.PAD + column * (roleWidth + 6), y + row * 36, roleWidth, function()
            chosen[role] = not chosen[role] or nil
            onToggle()
        end, chosen[role] and "selected" or "plain", 30)
    end
    return y + math.ceil(#roles / perRow) * 36 + 4
end

function Page.tagChips(listing)
    local tags = {}
    for _, tag in ipairs(Listing.TAGS) do
        if listing.tags and listing.tags[tag] then tags[#tags + 1] = { text = Listing.tagLabel(tag), kind = "tag" } end
    end
    return tags
end

return Page
