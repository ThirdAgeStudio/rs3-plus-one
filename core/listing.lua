-- core/listing.lua: a listing's tags, and the line of text a board row shows for one

local Listing = {}

Listing.TAGS = { "lootshare", "learner", "teacher", "chill", "combat_achievement", "reaper_task_only" }
local TAG_LABEL = {
    lootshare = "LootShare",
    learner = "Learner",
    teacher = "Teacher",
    chill = "Chill",
    combat_achievement = "Combat achievement",
    reaper_task_only = "Reaper task only",
}

function Listing.tagLabel(tag)
    return TAG_LABEL[tag]
end

-- each role once, in the order given, with repeats counted to save space 
-- { "Bomb Tank", "DPS x2" }
function Listing.grouped(roles)
    local counts, order = {}, {}
    for _, role in ipairs(roles) do
        if not counts[role] then order[#order + 1] = role end
        counts[role] = (counts[role] or 0) + 1
    end
    local grouped = {}
    for index, role in ipairs(order) do
        grouped[index] = counts[role] > 1 and string.format("%s x%d", role, counts[role]) or role
    end
    return grouped
end

function Listing.filledRoles(listing)
    local roles = {}
    for _, role in ipairs(listing.hostRoles or {}) do roles[#roles + 1] = role end
    for _, member in ipairs(listing.members or {}) do
        for _, role in ipairs(member.roles or {}) do roles[#roles + 1] = role end
    end
    return roles
end

return Listing
