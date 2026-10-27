-- ui/full.lua

local W = require("ui/widgets")
local Page = require("ui/page")
local Parties = require("ui/parties")
local ReaperTab = require("ui/reaper_tab")

local Full = {}

local PAD = Page.PAD
local TABS_HEIGHT, FOOTER_HEIGHT = 46, 50

local tab = "parties"
-- set by each draw, so a poll can redraw parts of the view
local refresh = function() return false end

function Full.tab()
    return tab
end

function Full.showTab(name)
    tab = name
    Page.clear()
end

local function drawFooter(layer, width, state)
    W.box(layer, 1, 0, width - 2, 1, W.BAR_EDGE)
    local busy = Page.busy(state)
    if state.notice then
        local noticeWidth = width - PAD * 2 - (tab == "reaper" and 0 or 150)
        W.label(layer, W.escape(state.notice), PAD, 16, noticeWidth, W.PROBLEM)
    end
    if tab == "reaper" then
        local text = not state.notice and ReaperTab.footer(state)
        if text then W.label(layer, text, PAD, 16, width - PAD * 2, W.GREEN) end
        return
    end
    local online = not state.notice and state.stats and state.stats.online
    if online and online > 0 then
        W.label(layer, string.format("%d %s online", online, online == 1 and "player" or "players"), PAD, 16, 160, W.GREEN)
    end
    W.button(layer, "+ Post a listing", width - PAD - 140, 8, 140, not busy and function() Page.act("post") end or nil,
        busy and "off" or "gold", 34)
end

function Full.draw(layer, width, state, height, onAction)
    Page.setAction(onAction)
    local tabs, body, footer, show
    local function drawTabs(name)
        tabs:DeleteAll()
        W.box(tabs, 1, TABS_HEIGHT - 1, width - 2, 1, W.BAR_EDGE)
        local half = (width - PAD * 2 - 4) // 2
        local function switchTo(to)
            return function()
                Page.clear()
                show(to)
            end
        end
        local pooled = state.poolPlayers
        W.button(tabs, string.format("Parties (%d)", #Parties.open(state)), PAD, 8, half, switchTo("parties"),
            name == "parties" and "selected" or "plain", 30)
        W.button(tabs, pooled and string.format("Reaper n Chill (%d)", pooled) or "Reaper n Chill", PAD + half + 4, 8,
            half, switchTo("reaper"), name == "reaper" and "green" or "plain", 30)
    end
    show = function(name)
        tab = name
        drawTabs(name)

        -- the pages that end in their own full-width button take the footer's space too
        local function fullPage()
            if name == "parties" then return Parties.fullPage() end
            return ReaperTab.fullPage()
        end
        local function drawBody()
            body:DeleteAll()
            local bodyHeight = height - TABS_HEIGHT - (fullPage() and 0 or FOOTER_HEIGHT)
            if name == "parties" then
                Parties.draw(body, width, bodyHeight, state)
            else
                ReaperTab.draw(body, width, bodyHeight, state)
            end
        end
        local wasFull = fullPage()
        drawBody()
        -- a page whose subject went (the listing closed) falls back to the tab, which has the footer
        if wasFull and not fullPage() then drawBody() end
        footer:DeleteAll()
        if not fullPage() then drawFooter(footer, width, state) end
    end
    tabs = ui.Layer.new(layer)
    tabs:SetSize(width, TABS_HEIGHT)
    body = ui.Layer.new(layer)
    body:SetPos(0, TABS_HEIGHT)
    body:SetSize(width, height - TABS_HEIGHT)
    footer = ui.Layer.new(layer)
    footer:SetPos(0, height - FOOTER_HEIGHT)
    footer:SetSize(width, FOOTER_HEIGHT)
    show(tab)
    refresh = function()
        if tab ~= "parties" or not Parties.refresh(state) then return false end
        drawTabs(tab)
        footer:DeleteAll()
        drawFooter(footer, width, state)
        return true
    end
end

function Full.refresh()
    return refresh()
end

return Full
