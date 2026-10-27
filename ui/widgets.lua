-- ui/widgets.lua
-- the game can't round corners, so rounded boxes are rectangles stepping in at each corner

local Log = require("log")

local Widgets = {}

-- a hook's error would otherwise reach the game with the layer half rebuilt and nothing logged
local function guarded(name, run)
    return function(...)
        local ok, err = pcall(run, ...)
        if not ok then Log.error("%s failed: %s", name, tostring(err)) end
    end
end

-- worlds saved in PersistentDB come back as floats
function Widgets.world(world)
    return tostring(math.tointeger(world) or world or "?")
end

Widgets.PANEL, Widgets.BAR_EDGE = 0x12181DFF, 0x2C3742FF
Widgets.CARD, Widgets.EDGE, Widgets.ROW_LINE = 0x1C262DFF, 0x3A4651FF, 0x222C34FF
Widgets.TEXT, Widgets.MUTED, Widgets.SOFT = 0xE6DCC3FF, 0xA9B6C2FF, 0xC3CDD6FF
Widgets.GOLD, Widgets.GREEN, Widgets.PROBLEM = 0xE8C46AFF, 0x8FD19BFF, 0xE88A7AFF

local function try(read)
    local ok, value = pcall(read)
    if ok then return value end
    return nil
end

-- an id name the client doesn't know reads as -1 (not nil cuz why not 🍝)
local function font(name, fallback)
    local value = try(function() return id.Font[name] end)
    if type(value) == "number" and value >= 0 then return value end
    return fallback
end

local BODY_FONT = font("VERDANA_11PT_REGULAR", 18)
local BOLD_FONT = font("VERDANA_11PT_BOLD", BODY_FONT)
local TITLE_FONT = font("MUSEO_SANS_15PT_REGULAR", BOLD_FONT)
local FONTS = { body = BODY_FONT, bold = BOLD_FONT, title = TITLE_FONT }

function Widgets.label(parent, value, x, y, width, colour, style, right)
    local text = ui.Text.new(parent)
    text:SetPos(x, y)
    text:SetSize(width, style == "title" and 22 or 18)
    text.font = FONTS[style or "body"] or BODY_FONT
    text.content, text.rgba, text.isShadowed, text.clickthrough = value, colour or Widgets.TEXT, false, true
    if right then text.alignHorizontal = ui.AlignMode.BOTTOMRIGHT end
    text.maxLines = 1
    return text
end

-- the game reads < as a formatting tag, so another player's text could restyle itself
function Widgets.escape(text)
    return (tostring(text):gsub("<", "<lt>"))
end

function Widgets.box(parent, x, y, width, height, colour)
    local rect = ui.Rectangle.new(parent)
    rect:SetPos(x, y)
    rect:SetSize(width, height)
    rect.rgba, rect.fill, rect.clickthrough = colour, true, true
    return rect
end

local insetCache = {}
local function cornerInsets(radius)
    if insetCache[radius] then return insetCache[radius] end
    local insets = {}
    for row = 0, radius - 1 do
        local inset = radius - math.floor(math.sqrt(radius * radius - (radius - row - 0.5) ^ 2) + 0.5)
        if inset <= 0 then break end
        insets[#insets + 1] = inset
    end
    insetCache[radius] = insets
    return insets
end

function Widgets.roundedBox(parent, x, y, width, height, colour, radius)
    local insets = cornerInsets(math.min(radius or 0, math.floor(height / 2), math.floor(width / 2)))
    local rows = #insets
    local parts = { Widgets.box(parent, x, y + rows, width, height - rows * 2, colour) }
    for row, inset in ipairs(insets) do
        parts[#parts + 1] = Widgets.box(parent, x + inset, y + row - 1, width - inset * 2, 1, colour)
        parts[#parts + 1] = Widgets.box(parent, x + inset, y + height - row, width - inset * 2, 1, colour)
    end
    return parts
end

function Widgets.panel(parent, x, y, width, height, fill, edge, radius)
    radius = radius or 0
    Widgets.roundedBox(parent, x, y, width, height, edge, radius)
    return Widgets.roundedBox(parent, x + 1, y + 1, width - 2, height - 2, fill, math.max(0, radius - 1))
end

local function recolour(parts, colour)
    for _, part in ipairs(parts) do part.rgba = colour end
end

local BUTTON_STYLES = {
    plain = { fill = 0x1C262DFF, hover = 0x26333CFF, edge = 0x3A4651FF, text = 0xC3CDD6FF },
    gold = { fill = 0x3A2F17FF, hover = 0x4A3C1DFF, edge = 0xC9A24CFF, text = 0xF2D58AFF, bold = true },
    green = { fill = 0x1F3325FF, hover = 0x284232FF, edge = 0x5F8F6AFF, text = 0xA8E0B2FF, bold = true },
    selected = { fill = 0x2E2716FF, hover = 0x2E2716FF, edge = 0xE8C46AFF, text = 0xF2D58AFF, bold = true },
    off = { fill = 0x161D23FF, hover = 0x161D23FF, edge = 0x2C3742FF, text = 0x6F7C88FF },
}
local BUTTON_RADIUS = 5

local function centredText(parent, value, colour, bold)
    local text = ui.Text.new(parent)
    text:SetPos(0, 0)
    text:SetSize(0, 0, 1.0, 1.0)
    text.font = bold and BOLD_FONT or BODY_FONT
    text.content, text.rgba, text.clickthrough = value, colour, true
    text.alignHorizontal, text.alignVertical, text.maxLines = ui.AlignMode.CENTRE, ui.AlignMode.CENTRE, 1
    return text
end

-- the click returns false, since this handles it fully
-- hovers return true, so other listeners still run
function Widgets.button(parent, value, x, y, width, onPress, styleName, height)
    local style = BUTTON_STYLES[styleName or "plain"]
    height = height or 30
    local root = ui.Layer.new(parent)
    root:SetPos(x, y)
    root:SetSize(width, height)
    root.clickthrough = false
    local fill = Widgets.panel(root, 0, 0, width, height, style.fill, style.edge, BUTTON_RADIUS)
    centredText(root, value, style.text, style.bold)
    root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        recolour(fill, style.hover)
        return true
    end)
    root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        recolour(fill, style.fill)
        return true
    end)
    if onPress then
        local press = guarded("button " .. tostring(value), onPress)
        root:Subscribe(ui.Hook.ONCLICK, function()
            press()
            return false
        end)
    end
    return root
end

-- without the game's INPUT_DEFAULT style the field draws no text and takes no typing
-- rebuilding a field loses the player's typing focus, so nothing redraws one while it can be typed in
function Widgets.input(parent, value, x, y, width, onChange, height)
    local field = ui.InputField.new(parent)
    pcall(function() field.stylesheetID = id.StyleSheet.INPUT_DEFAULT end)
    field:SetPos(x, y)
    field:SetSize(width, height or 34)
    field.content = value or ""
    if onChange then
        local change = guarded("input", onChange)
        field:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, _, content)
            change(tostring(content or field.content or ""))
            return true
        end)
    end
    return field
end

-- the API can't measure text, so widths are estimated at about 7px a character
local CHAR_WIDTH = 7

function Widgets.textWidth(text)
    return #tostring(text):gsub("<[^>]*>", "") * CHAR_WIDTH
end

local PIP, PIP_GAP = 11, 3
local MAX_PIPS = 10

function Widgets.pips(parent, x, y, filled, open)
    filled = math.min(filled, MAX_PIPS)
    open = math.min(open, MAX_PIPS - filled)
    for index = 0, filled + open - 1 do
        local left = x + index * (PIP + PIP_GAP)
        if index < filled then
            Widgets.roundedBox(parent, left, y, PIP, PIP, Widgets.GOLD, 2)
        else
            Widgets.panel(parent, left, y, PIP, PIP, Widgets.PANEL, Widgets.GREEN, 2)
        end
    end
    return (filled + open) * (PIP + PIP_GAP) - PIP_GAP
end

-- filled and needed chips differ in fill as well as colour, so they read apart without colour vision
local CHIP_HEIGHT = 20
local CHIP_STYLES = {
    filled = { fill = 0x2F5A37FF, edge = Widgets.GREEN, text = 0xE2F4E5FF, radius = 4 },
    needed = { fill = Widgets.PANEL, edge = Widgets.SOFT, text = 0xF2F4F6FF, radius = 4 },
    tag = { fill = 0x202A32FF, edge = 0x202A32FF, text = Widgets.MUTED, radius = CHIP_HEIGHT // 2 },
}
local function chip(parent, text, x, y, kind)
    local style = CHIP_STYLES[kind] or CHIP_STYLES.tag
    local width = Widgets.textWidth(text) + 14
    Widgets.panel(parent, x, y, width, CHIP_HEIGHT, style.fill, style.edge, style.radius)
    Widgets.label(parent, Widgets.escape(text), x + 7, y + 2, width - 10, style.text, kind ~= "tag" and "bold" or nil)
    return width
end

local function layChips(items, width, place)
    local left, top = 0, 0
    for _, item in ipairs(items) do
        local chipWidth = Widgets.textWidth(item.text) + 14
        if left > 0 and left + chipWidth > width then left, top = 0, top + CHIP_HEIGHT + 4 end
        place(item, left, top)
        left = left + chipWidth + 4
    end
    return #items > 0 and (top + CHIP_HEIGHT) or 0
end

function Widgets.chipsHeight(items, width)
    return layChips(items, width, function() end)
end

function Widgets.fitChips(items, width, dropIndex)
    local kept, hidden = { table.unpack(items) }, 0
    local function lineWidth()
        local used = hidden > 0 and Widgets.textWidth("+" .. hidden) + 14 or -4
        for _, item in ipairs(kept) do used = used + 4 + Widgets.textWidth(item.text) + 14 end
        return used
    end
    while #kept > 0 and lineWidth() > width do
        table.remove(kept, dropIndex and dropIndex(kept) or #kept)
        hidden = hidden + 1
    end
    if hidden > 0 then kept[#kept + 1] = { text = "+" .. hidden, kind = "tag" } end
    return kept
end

function Widgets.chips(parent, items, x, y, width)
    return layChips(items, width, function(item, left, top)
        chip(parent, item.text, x + left, y + top, item.kind)
    end)
end

function Widgets.pill(parent, text, right, y, fill, colour)
    local width = Widgets.textWidth(text) + 16
    Widgets.roundedBox(parent, right - width, y, width, 18, fill, 9)
    Widgets.label(parent, text, right - width + 8, y + 1, width - 10, colour, "bold")
end

function Widgets.stat(parent, label, value, x, y, width)
    Widgets.label(parent, label, x, y, width, Widgets.MUTED)
    Widgets.label(parent, value, x, y + 15, width, Widgets.TEXT, "bold")
end

function Widgets.stepper(parent, x, y, value, onMinus, onPlus)
    Widgets.button(parent, "-", x, y, 28, onMinus, onMinus and "plain" or "off", 26)
    Widgets.label(parent, tostring(value), x + 32, y + 4, 20, Widgets.TEXT, "bold")
    Widgets.button(parent, "+", x + 56, y, 28, onPlus, onPlus and "plain" or "off", 26)
    return 84
end

-- the knob slides before onPress runs, since onPress usually redraws the view and it would jump
local SWITCH_WIDTH, SWITCH_HEIGHT = 36, 18
local SLIDE_FRAMES = 8
local slides = 0
function Widgets.switch(parent, x, y, on, onPress)
    local root = ui.Layer.new(parent)
    root:SetPos(x, y)
    root:SetSize(SWITCH_WIDTH, SWITCH_HEIGHT)
    root.clickthrough = false
    Widgets.panel(root, 0, 0, SWITCH_WIDTH, SWITCH_HEIGHT, on and 0x2F5A3BFF or Widgets.CARD,
        on and Widgets.GREEN or Widgets.EDGE, SWITCH_HEIGHT // 2)
    local size = SWITCH_HEIGHT - 6
    local left, right = 3, SWITCH_WIDTH - size - 3
    local knob = ui.Layer.new(root)
    knob:SetSize(size, size)
    knob.clickthrough = true
    knob:SetPos(on and right or left, 3)
    Widgets.roundedBox(knob, 0, 0, size, size, on and Widgets.GREEN or Widgets.SOFT, size // 2)
    if onPress then
        local sliding = false
        root:Subscribe(ui.Hook.ONCLICK, function()
            if sliding then return false end
            sliding = true
            slides = slides + 1
            local key, frame = "plus-one-switch-" .. slides, 0
            local from, to = on and right or left, on and left or right
            Event.Logic.Subscribe(key, function()
                frame = frame + 1
                local done = frame >= SLIDE_FRAMES
                pcall(function()
                    local eased = 1 - (1 - frame / SLIDE_FRAMES) ^ 2
                    knob:SetPos(math.floor(from + (to - from) * math.min(1, eased) + 0.5), 3)
                end)
                if done then
                    Event.Logic.Unsubscribe(key)
                    guarded("switch", onPress)()
                end
            end)
            return false
        end)
    end
    return root
end

return Widgets
