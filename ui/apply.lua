-- ui/apply.lua

local W = require("ui/widgets")
local Page = require("ui/page")
local Kills = require("game/kills")

local Apply = {}

local PAD = Page.PAD

local chosenRoles = {}
local problem = nil

function Apply.open(listingId)
    chosenRoles, problem = {}, nil
    Page.open("apply", listingId)
end

function Apply.problem(message)
    problem = message
end

local function drawListing(layer, width, y, listing)
    local cardWidth = width - PAD * 2
    local _, chips = Page.roleChips(listing)
    for _, chip in ipairs(Page.tagChips(listing)) do chips[#chips + 1] = chip end
    local chipsHeight = #chips > 0 and (W.chipsHeight(chips, cardWidth - 24) + 8) or 0
    W.panel(layer, PAD, y, cardWidth, 56 + chipsHeight, W.CARD, W.EDGE, Page.CARD_RADIUS)
    W.chips(layer, chips, PAD + 12, y + 52, cardWidth - 24)
    W.label(layer, Page.activityName(listing.activity), PAD + 12, y + 8, cardWidth - 100, W.TEXT, "title")
    W.pips(layer, PAD + 12, y + 34, listing.filled, listing.size - listing.filled)
    W.label(layer, "WORLD", PAD, y + 9, cardWidth - 12, W.MUTED, nil, true)
    W.label(layer, W.world(listing.world), PAD, y + 25, cardWidth - 12, W.TEXT, "bold", true)
    return 56 + chipsHeight
end

function Apply.draw(layer, width, height, listing, name)
    local cardWidth = width - PAD * 2
    local y = Page.backBar(layer, width, "Apply to " .. W.escape(listing.host))
    y = y + drawListing(layer, width, y, listing) + 10

    local roles, seen = {}, {}
    for _, role in ipairs(listing.needs or {}) do
        if not seen[role] then roles[#roles + 1], seen[role] = role, true end
    end
    if #roles > 0 then
        Page.header(layer, width, y, "Apply as", "pick one or more")
        y = y + 22
        y = Page.roleToggles(layer, width, y, roles, chosenRoles, function()
            problem = nil
            Page.act("redraw")
        end)
    end

    -- name, kills and combat level for now
    Page.header(layer, width, y, "Sent to host")
    y = y + 22
    local sent = {
        { "DISPLAY NAME", W.escape(name or "?") },
        { string.upper(Page.activityName(listing.activity)) .. " KILLS", tostring(Kills.of(listing.activity)) },
        { "COMBAT", tostring(Kills.combat()) },
    }
    local perRow = 3
    local column = cardWidth // perRow
    for index, stat in ipairs(sent) do
        local row, place = (index - 1) // perRow, (index - 1) % perRow
        W.stat(layer, stat[1], stat[2], PAD + place * column, y + row * 40, column - 6)
    end
    y = y + math.ceil(#sent / perRow) * 40

    local chosen = {}
    for _, role in ipairs(roles) do
        if chosenRoles[role] then chosen[#chosen + 1] = role end
    end
    Page.problemLine(layer, width, height, problem)
    -- a listing with a full queue of applications waiting takes no more until the host answers some
    local label = listing.busy and "Busy" or (#roles == 0 or #chosen > 0) and "Send application" or "Pick a role first"
    local ready = label == "Send application"
    Page.sendButton(layer, label, "apply", PAD, height - PAD - 40, cardWidth,
        ready and function() Page.act("apply", { listing = listing, roles = chosen }) end or nil,
        ready and "gold" or "off", 40, "Sending...")
end

return Apply
