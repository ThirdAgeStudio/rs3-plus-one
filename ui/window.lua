-- ui/window.lua
-- closed by default for now

local W = require("ui/widgets")
local Snap = require("ui/snap")
local Log = require("log")

local Window = {}
Window.__index = Window

local TITLE_HEIGHT = 24
local STORE_KEY = "window"

function Window.new(sizes, draw)
    local ok, saved = pcall(function() return PersistentDB:GetStructuredData(STORE_KEY) end)
    if not ok or type(saved) ~= "table" then saved = {} end
    return setmetatable({
        sizes = sizes, draw = draw,
        x = tonumber(saved.x) or 120, y = tonumber(saved.y) or 120,
        view = sizes[saved.view] and saved.view or "full",
        anchorX = saved.anchorX, anchorY = saved.anchorY,
        root = nil,
    }, Window)
end

function Window:isOpen() return self.root ~= nil end

function Window:save()
    pcall(function()
        PersistentDB:SetStructuredData(STORE_KEY, {
            x = self.x, y = self.y, view = self.view, anchorX = self.anchorX, anchorY = self.anchorY,
        })
    end)
end

function Window:place(x, y)
    local size = self.sizes[self.view]
    local maxX = math.max(0, self.parent.width - size[1])
    local maxY = math.max(0, self.parent.height - TITLE_HEIGHT)
    self.x = math.floor(math.max(0, math.min(maxX, x)))
    self.y = math.floor(math.max(0, math.min(maxY, y)))
    self.root:SetPos(self.x, self.y)
end

function Window:dragTo(x, y)
    local size = self.sizes[self.view]
    local snappedX, snappedY, labels, edges = Snap.position(x, y, size[1], size[2], self.parent, self.snapRects or {})
    self.snappedTo, self.snappedEdges = labels, edges
    self:place(snappedX, snappedY)
end

-- mouse hooks only report positions over their own component
function Window:coverTitle()
    self.handle:SetPos(self.x, self.y)
    self.handle:SetSize(self.sizes[self.view][1] - 104, TITLE_HEIGHT)
end

function Window:makeDraggable()
    local handle = ui.Layer.new(self.parent)
    handle.clickthrough = false
    self.handle = handle
    self:coverTitle()

    local grab = nil
    local function stop()
        if grab == nil then return true end
        grab = nil
        self:coverTitle()
        local size = self.sizes[self.view]
        self.anchorX, self.anchorY = Snap.anchors(self.x, self.y, size[1], size[2], self.parent, self.snappedEdges)
        self:save()
        Log.log("window", "placed at %d,%d, snapped %s / %s, holding %s %s", self.x, self.y,
            tostring(self.snappedTo and self.snappedTo[1] or "no x"), tostring(self.snappedTo and self.snappedTo[2] or "no y"),
            tostring(self.anchorX), tostring(self.anchorY))
        return true
    end
    handle:Subscribe(ui.Hook.ONCLICK, function(_, mouseX, mouseY)
        if type(mouseX) ~= "number" or type(mouseY) ~= "number" then return true end
        grab = { x = mouseX, y = mouseY }
        local found, rects = pcall(Snap.findInterfaces, self.parent)
        self.snapRects = found and rects or {}
        handle:SetPos(0, 0)
        handle:SetSize(0, 0, 1.0, 1.0)
        handle:MoveToFront()
        return true
    end)
    handle:Subscribe(ui.Hook.ONHOLD, function(_, mouseX, mouseY)
        if grab == nil or type(mouseX) ~= "number" or type(mouseY) ~= "number" then return true end
        local ok, err = pcall(self.dragTo, self, mouseX - grab.x, mouseY - grab.y)
        if not ok then Log.error("drag failed: %s", tostring(err)) end
        return true
    end)
    handle:Subscribe(ui.Hook.ONRELEASE, stop)
    handle:Subscribe(ui.Hook.ONDRAGCOMPLETE, stop)
end

function Window:build()
    self.parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if self.parent == nil then
        Log.log("window", "no plugin build layer")
        return false
    end
    local width, height = self.sizes[self.view][1], self.sizes[self.view][2]
    self.root = ui.Layer.new(self.parent)
    self.root:SetSize(width, height)
    -- takes every click inside it, so a misclick doesn't walk or attack in the game behind
    self.root.clickthrough = false
    W.panel(self.root, 0, 0, width, height, W.PANEL, W.EDGE)
    W.box(self.root, 1, TITLE_HEIGHT - 1, width - 2, 1, W.BAR_EDGE)
    self.titleText = W.label(self.root, self.title or "Plus One", 10, 4, width - 110, W.GOLD, "bold")

    local other = self.view == "full" and "compact" or "full"
    W.button(self.root, other == "full" and "Full" or "Compact", width - 100, 2, 70, function() self:setView(other) end,
        "plain", 20)
    -- the plugin tab's button shows whether the window is open
    W.button(self.root, "X", width - 27, 2, 22, function() self:requestClose() end, "plain", 20)

    self.content = ui.Layer.new(self.root)
    self.content:SetPos(0, TITLE_HEIGHT)
    self.content:SetSize(width, height - TITLE_HEIGHT)
    self:place(self.x, self.y)
    self:makeDraggable()
    self:redraw()
    return true
end

function Window:setTitle(title)
    self.title = title
    if self.titleText ~= nil then self.titleText.content = title end
end

function Window:redraw()
    if self.content == nil then return end
    self.content:DeleteAll()
    local size = self.sizes[self.view]
    local ok, err = pcall(self.draw, self.view, self.content, size[1], size[2] - TITLE_HEIGHT)
    if not ok then Log.error("drawing %s failed: %s", self.view, tostring(err)) end
end

function Window:open()
    if self.root == nil then self:build() end
end

-- confirmClose can hold the window open to ask first, returning true while it asks
function Window:requestClose()
    if self.confirmClose and self.confirmClose() then return end
    self:close()
    if self.onClosed then self.onClosed() end
end

function Window:close()
    if self.root ~= nil then pcall(function() self.root:Destroy() end) end
    if self.handle ~= nil then pcall(function() self.handle:Destroy() end) end
    self.root, self.content, self.handle = nil, nil, nil
end

-- the snapped edges stay put, so a window snapped right or bottom stays there in either view
function Window:setView(view)
    local old, new = self.sizes[self.view], self.sizes[view]
    if self.anchorX == nil and self.parent then
        self.anchorX, self.anchorY = Snap.anchors(self.x, self.y, old[1], old[2], self.parent, nil)
    end
    if self.anchorX == "right" then self.x = self.x + old[1] - new[1] end
    if self.anchorY == "bottom" then self.y = self.y + old[2] - new[2] end
    self.view = view
    self:save()
    self:close()
    self:build()
end

return Window
