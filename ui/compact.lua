-- ui/compact.lua

local W = require("ui/widgets")
local Page = require("ui/page")

local Compact = {}

-- the keys main.lua's requests wait under
local WAITING_KEY = { close_listing = "close_listing", pool_leave = "pool_leave", withdraw = "withdraw", dismiss = "withdraw" }

local ACTION_LABEL = {
    close_listing = "Close listing", pool_leave = "Leave", withdraw = "Withdraw", dismiss = "Dismiss",
    browse = "Browse", join_pool = "Reaper pool",
}

function Compact.draw(layer, width, status, act)
    local y = 8
    W.label(layer, status.title, 10, y, width - 20, W.TEXT, "bold")
    y = y + 20
    if status.detail then
        W.label(layer, W.escape(status.detail), 10, y, width - 20, W.MUTED)
        y = y + 20
    end
    if status.notice then
        W.label(layer, W.escape(status.notice), 10, y, width - 20, W.PROBLEM)
        y = y + 20
    end
    if status.ask then
        W.label(layer, W.escape(status.ask.text), 10, y + 2, width - 20, W.GOLD)
        y = y + 24
        local pool = status.ask.kind == "request"
        local key = (pool and "answer:" or "decide:") .. status.ask.id
        Page.sendButton(layer, "Accept", key, 10, y, 76, function() act(pool and "pool_accept" or "accept", status.ask.id) end,
            "gold", 26)
        Page.sendButton(layer, "Decline", key, 92, y, 76, function() act(pool and "pool_decline" or "decline", status.ask.id) end,
            "plain", 26)
        if status.more > 0 then W.label(layer, string.format("+%d more", status.more), 176, y + 4, 60, W.MUTED) end
        y = y + 32
    end
    local x = 10
    for _, action in ipairs(status.actions) do
        Page.sendButton(layer, ACTION_LABEL[action] or action, WAITING_KEY[action] or action, x, y, 96,
            function() act(action) end, "plain", 26)
        x = x + 102
    end
    return y + 32
end

return Compact
