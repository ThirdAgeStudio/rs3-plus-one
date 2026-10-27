-- ui/applications.lua

local W = require("ui/widgets")
local Page = require("ui/page")
local Pager = require("core/pager")

local Applications = {}

local PAD = Page.PAD
local CARD = 58
local shownPage = 1

function Applications.draw(layer, width, height, listing)
    local cardWidth = width - PAD * 2
    local y = Page.backBar(layer, width, "Applications to " .. Page.activityName(listing.activity))
    W.label(layer, string.format("%d/%d", listing.filled, listing.size), PAD, PAD + 6, cardWidth, W.SOFT, nil, true)
    local filled, needed = Page.roleChips(listing)
    for _, chip in ipairs(needed) do filled[#filled + 1] = chip end
    y = y + W.chips(layer, filled, PAD, y, cardWidth) + 8

    local waiting = listing.applications or {}
    local perPage = math.max(1, math.floor((height - y - Page.PAGER_HEIGHT) / (CARD + 6)))
    local shown, pages
    shown, shownPage, pages = Pager.page(waiting, perPage, shownPage)
    for _, application in ipairs(shown) do
        W.panel(layer, PAD, y, cardWidth, CARD, W.CARD, W.EDGE, Page.CARD_RADIUS)
        W.label(layer, W.escape(application.name), PAD + 10, y + 8, cardWidth - 120, W.TEXT, "bold")
        W.label(layer, W.escape(application.role), PAD + cardWidth - 160, y + 8, 150, W.GOLD, nil, true)
        W.label(layer, string.format("Kills %d, combat %d", application.kills or 0, application.combat or 0),
            PAD + 10, y + 32, cardWidth - 150, W.MUTED)
        Page.sendButton(layer, "Accept", "decide:" .. application.id, PAD + cardWidth - 140, y + 26, 64,
            function() Page.act("accept", application.id) end,
            "gold", 26)
        Page.sendButton(layer, "Decline", "decide:" .. application.id, PAD + cardWidth - 70, y + 26, 62,
            function() Page.act("decline", application.id) end,
            "plain", 26)
        y = y + CARD + 6
    end
    if #waiting == 0 then W.label(layer, "No applications waiting", PAD, y, cardWidth, W.MUTED) end

    if pages > 1 then
        Page.pager(layer, width, height - Page.PAGER_HEIGHT + 2, shownPage, pages, function(step)
            shownPage = shownPage + step
            Page.act("redraw")
        end)
    end
end

return Applications
