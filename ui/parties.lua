-- ui/parties.lua

local W = require("ui/widgets")
local Page = require("ui/page")
local Board = require("core/board")
local Pager = require("core/pager")
local Applications = require("ui/applications")
local Apply = require("ui/apply")
local Post = require("ui/post")

local Parties = {}

local PAD = Page.PAD
local LISTING_EDGE = 0xC9A24CFF
local CARD_HEIGHT = 118
-- the goal is to have static ui element sizes across the board for simplicity
local MIN_ROW_HEIGHT, ROW_PAD, NAME_HEIGHT, CHIP_LINE, SIDE_WIDTH, APPLY_HEIGHT = 90, 3, 22, 20, 64, 28

local search = ""
local boardPage = 1
local drawn = nil

local function drawOwnListing(layer, width, y, listing)
    local cardWidth = width - PAD * 2
    W.panel(layer, PAD, y, cardWidth, CARD_HEIGHT, W.CARD, LISTING_EDGE, Page.CARD_RADIUS)
    W.label(layer, Page.activityName(listing.activity), PAD + 12, y + 8, cardWidth - 140, W.TEXT, "title")
    W.label(layer, "YOUR LISTING", PAD + 12, y + 12, cardWidth - 24, W.GOLD, nil, true)
    local filled, needed = Page.roleChips(listing)
    W.chips(layer, W.fitChips(filled, cardWidth - 24), PAD + 12, y + 34, cardWidth - 24)
    W.chips(layer, W.fitChips(needed, cardWidth - 24), PAD + 12, y + 56, cardWidth - 24)
    local applied = #(listing.applications or {})
    W.button(layer, applied > 0 and string.format("%d new applications", applied) or "No applications yet",
        PAD + 12, y + 80, cardWidth - 24 - 76, applied > 0 and function() Page.act("open_applications") end or nil,
        applied > 0 and "gold" or "plain", 32)
    Page.sendButton(layer, "Close", "close_listing", PAD + cardWidth - 12 - 70, y + 80, 70, function() Page.act("close_listing") end,
        "plain", 32)
    return y + CARD_HEIGHT
end

local function drawOwnApplication(layer, width, y, applied, listing)
    local cardWidth = width - PAD * 2
    local party = applied.status == "accepted" and applied.party or nil
    local declined = applied.status == "declined"
    local spots = party or listing
    W.panel(layer, PAD, y, cardWidth, CARD_HEIGHT, party and 0x1D2A22FF or W.CARD,
        party and 0x4E7A59FF or LISTING_EDGE, Page.CARD_RADIUS)
    W.label(layer, party and "YOUR PARTY" or "YOUR APPLICATION", PAD + 12, y + 10, 200, party and W.GREEN or W.GOLD)
    W.pill(layer, party and "Accepted" or declined and "Declined" or "Pending", PAD + cardWidth - 12, y + 9,
        party and W.GREEN or declined and 0x5A2A2AFF or W.BAR_EDGE, party and W.PANEL or W.SOFT)
    W.label(layer, Page.activityName(applied.activity), PAD + 12, y + 30, cardWidth - 140, W.TEXT, "title")
    if spots then
        W.pips(layer, PAD + cardWidth - 12 - 14 * spots.size + 3, y + 37, spots.filled, spots.size - spots.filled)
    end

    local column = (cardWidth - 24 - 90) // 3
    local roles = applied.roles or {}
    W.stat(layer, "HOST", W.escape(applied.host or "?"), PAD + 12, y + 66, column - 4)
    W.stat(layer, "WORLD", W.world(applied.world), PAD + 12 + column, y + 66, column - 4)
    W.stat(layer, #roles > 1 and "ROLES" or "ROLE", W.escape(#roles > 0 and table.concat(roles, ", ") or "Any"),
        PAD + 12 + column * 2, y + 66, column - 4)
    Page.sendButton(layer, party and "Leave" or declined and "Dismiss" or "Withdraw", "withdraw", PAD + cardWidth - 12 - 84,
        y + 78, 84, function() Page.act("withdraw") end, "plain", 28)
    return y + CARD_HEIGHT
end

local function drawRow(rows, listing, width, y, height, canApply)
    local left, right = PAD + 2, width - PAD - 2
    local lineWidth = right - left
    local hostWidth = 120
    W.label(rows, Page.activityName(listing.activity), left, y + ROW_PAD, lineWidth - hostWidth - 8, W.TEXT, "title")
    W.label(rows, W.escape(listing.host or ""), right - hostWidth, y + ROW_PAD + 2, hostWidth, W.MUTED, nil, true)
    W.pill(rows, "W" .. W.world(listing.world), right, y + ROW_PAD + NAME_HEIGHT, W.CARD, W.TEXT)
    local besideApply = lineWidth - SIDE_WIDTH - 8
    local filled, needed = Page.roleChips(listing)
    local gap = (height - ROW_PAD * 2 - NAME_HEIGHT - CHIP_LINE * 3) // 3
    local lines = { { filled, besideApply }, { needed, besideApply }, { Page.tagChips(listing), besideApply } }
    for index, line in ipairs(lines) do
        local lineY = y + ROW_PAD + NAME_HEIGHT + gap * index + CHIP_LINE * (index - 1)
        W.chips(rows, W.fitChips(line[1], line[2]), left, lineY, line[2])
    end
    -- a listing with a full queue of applications waiting takes no more until the host answers some
    if listing.busy then
        W.button(rows, "Busy", right - SIDE_WIDTH, y + height - ROW_PAD - APPLY_HEIGHT, SIDE_WIDTH, nil, "off",
            APPLY_HEIGHT)
    else
        W.button(rows, "Apply", right - SIDE_WIDTH, y + height - ROW_PAD - APPLY_HEIGHT, SIDE_WIDTH,
            canApply and function() Page.act("open_apply", listing.id) end or nil, canApply and "gold" or "off",
            APPLY_HEIGHT)
    end
    W.box(rows, PAD, y + height - 1, width - PAD * 2, 1, W.ROW_LINE)
end

-- full parties are hidden for now
-- a future iteration will add a host step to confirm party
function Parties.open(state)
    local appliedTo = state.application and state.application.listing
    local open = {}
    for _, listing in ipairs(state.listings or {}) do
        if listing.filled < listing.size and listing.id ~= appliedTo then open[#open + 1] = listing end
    end
    return open
end

local function drawRows(rows, width, height, state)
    rows:DeleteAll()
    local matching = Board.view(Parties.open(state), state.prefs, search)
    local perPage = math.max(1, (height - Page.PAGER_HEIGHT) // MIN_ROW_HEIGHT)
    local rowHeight = (height - Page.PAGER_HEIGHT) // perPage
    local shown, pages
    shown, boardPage, pages = Pager.page(matching, perPage, boardPage)
    local canApply = not Page.busy(state)
    for index, listing in ipairs(shown) do drawRow(rows, listing, width, (index - 1) * rowHeight, rowHeight, canApply) end
    if #matching == 0 then W.label(rows, "No listings match", PAD + 2, 8, width - PAD * 2, W.MUTED) end

    if pages > 1 then
        Page.pager(rows, width, perPage * rowHeight + 2, boardPage, pages, function(step)
            boardPage = boardPage + step
            drawRows(rows, width, height, state)
        end)
    end
end

local function drawPage(layer, width, height, state)
    local name, data = Page.top()
    if name == "applications" and state.listing then
        Applications.draw(layer, width, height, state.listing)
        return true
    end
    local listing = name == "apply" and Page.findListing(state, data)
    if listing and not Page.busy(state) then
        Apply.draw(layer, width, height, listing, state.playerName)
        return true
    end
    if name == "post" and Post.isOpen() and not Page.busy(state) then
        Post.draw(layer, width, height)
        return true
    end
    if name then Page.clear() end
    return false
end

local function drawCards(layer, width, state)
    if state.listing then return drawOwnListing(layer, width, PAD, state.listing) + 10 end
    if state.application then
        return drawOwnApplication(layer, width, PAD, state.application, Page.findListing(state, state.application.listing)) + 10
    end
    return PAD
end

function Parties.draw(layer, width, height, state)
    drawn = nil
    if drawPage(layer, width, height, state) then return end
    local cards = ui.Layer.new(layer)
    local cardsEnd = drawCards(cards, width, state)
    cards:SetSize(width, cardsEnd)
    local y = cardsEnd
    local rows, rowsY
    local buttonWidth = 58
    local searchWidth = width - PAD * 2 - (buttonWidth + 6) * 2
    local hint
    local function matchingIds(text)
        local ids = {}
        for index, listing in ipairs(Board.view(Parties.open(state), state.prefs, text)) do ids[index] = listing.id end
        return table.concat(ids, " ")
    end
    W.input(layer, search, PAD, y, searchWidth, function(text)
        if text == search then return end
        local same = matchingIds(text) == matchingIds(search)
        search = text
        hint.hidden = text ~= ""
        if same then return end
        boardPage = 1
        drawRows(rows, width, height - rowsY, state)
    end, 32)
    hint = W.label(layer, "Search bosses or players", PAD + 10, y + 7, searchWidth - 20, 0x6F7C88FF)
    hint.hidden = search ~= ""
    W.button(layer, "Filter", width - PAD - buttonWidth * 2 - 6, y, buttonWidth, nil, "off", 32)
    W.button(layer, "Sort", width - PAD - buttonWidth, y, buttonWidth, nil, "off", 32)
    y = y + 32 + 8
    rowsY = y
    rows = ui.Layer.new(layer)
    rows:SetPos(0, y)
    rows:SetSize(width, height - y)
    drawRows(rows, width, height - y, state)
    drawn = { cards = cards, cardsEnd = cardsEnd, rows = rows, width = width, rowsHeight = height - y }
end

function Parties.refresh(state)
    if drawn == nil or Page.top() then return false end
    drawn.cards:DeleteAll()
    if drawCards(drawn.cards, drawn.width, state) ~= drawn.cardsEnd then return false end
    drawRows(drawn.rows, drawn.width, drawn.rowsHeight, state)
    return true
end

function Parties.fullPage()
    local name = Page.top()
    return name == "apply" or name == "post"
end

return Parties
