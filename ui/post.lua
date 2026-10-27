-- ui/post.lua
-- the host is one player whatever roles they take, and each friend's role and each role needed is another

local W = require("ui/widgets")
local Page = require("ui/page")
local Listing = require("core/listing")
local Activities = require("core/activities")

local Post = {}

local PAD = Page.PAD
local STEPPER = 84
local COLUMN_GAP = 12
local ROW = 30

local form = nil

function Post.open(world)
    form = { activity = Activities.all()[1].key, mine = {}, have = {}, needed = {}, world = world or "", tags = {} }
    Page.open("post")
end

function Post.isOpen()
    return form ~= nil
end

function Post.problem(message)
    if form then form.problem = message end
end

local function expand(counts, roles)
    local list = {}
    for _, role in ipairs(roles) do
        for _ = 1, counts[role] or 0 do list[#list + 1] = role end
    end
    return list
end

-- a world that isn't a whole number (1-259) is left out & the server refuses it with an error message
-- would like to use the hosts world when there's a good var for it in the future
local function fields()
    local activity = Activities.get(form.activity)
    local mine, friends, needs = {}, expand(form.have, activity.roles), expand(form.needed, activity.roles)
    for _, role in ipairs(activity.roles) do
        if form.mine[role] then mine[#mine + 1] = role end
    end
    local hostRoles = { table.unpack(mine) }
    for _, role in ipairs(friends) do hostRoles[#hostRoles + 1] = role end
    local filled = 1 + #friends
    return {
        activity = activity.key, size = filled + #needs, filled = filled, needs = needs, hostRoles = hostRoles,
        world = math.tointeger(tonumber(form.world)), tags = form.tags,
    }
end

local function change(apply)
    return function()
        apply()
        form.problem = nil
        Page.act("redraw")
    end
end

local function drawBosses(layer, width, y)
    local bosses = Activities.all()
    local bossWidth = math.floor((width - PAD * 2 - 6 * (#bosses - 1)) / #bosses)
    for index, boss in ipairs(bosses) do
        W.button(layer, boss.name, PAD + (index - 1) * (bossWidth + 6), y, bossWidth, change(function()
            form.activity, form.mine, form.have, form.needed = boss.key, {}, {}, {}
        end), boss.key == form.activity and "selected" or "plain", 30)
    end
    return y + 40
end

local function drawRoles(layer, width, y, activity)
    local cardWidth = width - PAD * 2
    local needX = PAD + cardWidth - STEPPER
    local haveX = needX - COLUMN_GAP - STEPPER
    W.label(layer, "Roles", PAD, y, 100, W.GOLD, "bold")
    W.label(layer, "have", haveX + 30, y + 1, STEPPER - 30, W.GREEN)
    W.label(layer, "need", needX + 30, y + 1, STEPPER - 30, W.TEXT)
    y = y + 22
    local listing = fields()
    local room = listing.size < activity.maxPlayers
    for _, role in ipairs(activity.roles) do
        W.label(layer, W.escape(role), PAD, y + 4, haveX - PAD - 8, W.TEXT)
        for _, column in ipairs({ { counts = form.have, x = haveX }, { counts = form.needed, x = needX } }) do
            local count = column.counts[role] or 0
            W.stepper(layer, column.x, y, count,
                count > 0 and change(function() column.counts[role] = count - 1 end) or nil,
                room and change(function() column.counts[role] = count + 1 end) or nil)
        end
        y = y + ROW
    end
    local filled, needed = Page.roleChips(listing)
    for _, chip in ipairs(needed) do filled[#filled + 1] = chip end
    if #filled > 0 then y = y + 4 + W.chips(layer, filled, PAD, y + 4, cardWidth) end
    return y + 10
end

local function drawTags(layer, width, y)
    local left = PAD
    for _, tag in ipairs(Listing.TAGS) do
        local label = Listing.tagLabel(tag)
        local tagWidth = W.textWidth(label) + 18
        if left > PAD and left + tagWidth > width - PAD then left, y = PAD, y + 30 end
        W.button(layer, label, left, y, tagWidth, change(function() form.tags[tag] = not form.tags[tag] or nil end),
            form.tags[tag] and "selected" or "plain", 26)
        left = left + tagWidth + 5
    end
end

function Post.draw(layer, width, height)
    local activity = Activities.get(form.activity)
    local y = Page.backBar(layer, width, "Post a listing")
    y = drawBosses(layer, width, y)
    Page.header(layer, width, y, "Your role", "pick one or more")
    y = Page.roleToggles(layer, width, y + 22, activity.roles, form.mine, function()
        form.problem = nil
        Page.act("redraw")
    end)
    y = drawRoles(layer, width, y + 4, activity)

    W.label(layer, "World", PAD, y + 8, 60, W.GOLD, "bold")
    W.input(layer, form.world, PAD + 60, y, 80, function(text) form.world = text end, 30)
    drawTags(layer, width, y + 40)

    local cardWidth = width - PAD * 2
    Page.problemLine(layer, width, height, form.problem)
    local hasRole = next(form.mine) ~= nil or #activity.roles == 0
    Page.sendButton(layer, hasRole and "Post listing" or "Pick your role first", "post_send", PAD, height - PAD - 40,
        cardWidth, hasRole and function() Page.act("post_send", fields()) end or nil, hasRole and "gold" or "off", 40,
        "Posting...")
end

return Post
