-- ui/snap.lua

local Log = require("log")

local Snap = {}

local SNAP = 12

-- interfaces that come and go or cover the game view are never lined up with
local NOT_SNAPPED = {
    XP_POPUP = true, MESBOX_V2 = true, SPLIT_PM = true, PLAYER_INSPECT = true, GRAVESTONE_TIMER = true,
    COMBATV2_CHANNEL_BAR = true,
    POH_HOUSE_CONTROLS = true,
}

local function closest(value, candidates)
    local best, bestDistance, label, edge = value, SNAP + 1, nil, nil
    for _, candidate in ipairs(candidates) do
        local distance = math.abs(value - candidate[1])
        if distance < bestDistance then
            best, bestDistance, label, edge = candidate[1], distance, candidate[2], candidate[3]
        end
    end
    return best, label, edge
end

-- the API has no list of open interfaces, so every id is tried
-- the frame the player sees is component 0's outermost parent that isn't screen-sized
function Snap.findInterfaces(parent)
    local rects, tried, open = {}, 0, 0
    local screenWidth, screenHeight = parent.width, parent.height
    for key, value in pairs(id.Interface) do
        local interfaceId = type(key) == "number" and key or value
        local name = type(key) == "number" and value or key
        if type(interfaceId) == "number" and interfaceId >= 0 then
            tried = tried + 1
            pcall(function()
                if ui.Interfaces:GetInterface(interfaceId) == nil then return end
                open = open + 1
                local root = ui.Interfaces:GetComponent(interfaceId << 16)
                if root == nil or root.visibleGlobal == false then return end
                local frame, depth = root, 0
                while depth < 6 do
                    local ok, above = pcall(function() return frame.parent end)
                    if not ok or above == nil then break end
                    if above.width >= screenWidth / 2 and above.height >= screenHeight / 2 then break end
                    frame, depth = above, depth + 1
                end
                local at, width, height = frame.xyGlobal, frame.width, frame.height
                -- the game view and the layers over it are most of the screen
                if width <= 4 or height <= 4 or (width >= screenWidth / 2 and height >= screenHeight / 2) then return end
                if NOT_SNAPPED[tostring(name)] then return end
                rects[#rects + 1] = { x = at.x, y = at.y, width = width, height = height, name = tostring(name) }
            end)
        end
    end
    Log.log("window", "interfaces: %d ids tried, %d open, %d to snap to", tried, open, #rects)
    return rects
end

function Snap.position(x, y, width, height, parent, rects)
    local xs = { { 0, "screen left", "left" }, { parent.width - width, "screen right", "right" } }
    local ys = { { 0, "screen top", "top" }, { parent.height - height, "screen bottom", "bottom" } }
    for _, rect in ipairs(rects) do
        if y < rect.y + rect.height + SNAP and y + height > rect.y - SNAP then
            xs[#xs + 1] = { rect.x - width, "left of " .. rect.name, "right" }
            xs[#xs + 1] = { rect.x + rect.width, "right of " .. rect.name, "left" }
            xs[#xs + 1] = { rect.x, "flush left with " .. rect.name, "left" }
            xs[#xs + 1] = { rect.x + rect.width - width, "flush right with " .. rect.name, "right" }
        end
        if x < rect.x + rect.width + SNAP and x + width > rect.x - SNAP then
            ys[#ys + 1] = { rect.y - height, "above " .. rect.name, "bottom" }
            ys[#ys + 1] = { rect.y + rect.height, "below " .. rect.name, "top" }
            ys[#ys + 1] = { rect.y, "flush top with " .. rect.name, "top" }
            ys[#ys + 1] = { rect.y + rect.height - height, "flush bottom with " .. rect.name, "bottom" }
        end
    end
    local snappedX, labelX, edgeX = closest(x, xs)
    local snappedY, labelY, edgeY = closest(y, ys)
    return snappedX, snappedY, { labelX, labelY }, { edgeX, edgeY }
end

-- the snapped edge holds still when the size changes, or else the edge nearer the screen's side
function Snap.anchors(x, y, width, height, parent, edges)
    local horizontal = edges and edges[1] or ((x + width / 2 > parent.width / 2) and "right" or "left")
    local vertical = edges and edges[2] or ((y + height / 2 > parent.height / 2) and "bottom" or "top")
    return horizontal, vertical
end

return Snap
