-- core/activities.lua: what a listing can be for
-- only these can be listed, since describing anything else would need free text
-- roles sourced from PvME and the the rs wiki

local Activities = {}

local LIST = {
    -- standard bosses
    { key = "vorago", name = "Vorago", maxPlayers = 10, roles = { "Base Tank", "Bomb Tank", "TL5", "DPS" } },
    { key = "solak", name = "Solak", maxPlayers = 7, roles = { "Base", "Mind Tank", "DPS" } },
    -- skilling bosses
    { key = "croesus", name = "Croesus", maxPlayers = 9, roles = { "Hunter", "Mining", "Woodcutting", "Fishing", "Rotter" } },
}

local byKey = {}
for _, activity in ipairs(LIST) do byKey[activity.key] = activity end

function Activities.all()
    return LIST
end

function Activities.name(key)
    local activity = Activities.get(key)
    return activity and activity.name
end

function Activities.get(key)
    return byKey[key]
end

return Activities
