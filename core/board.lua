-- core/board.lua: the search, filter and sort the board applies to the listings the server sent
-- done on the client so typing in the search box doesn't send a request per key

local Activities = require("core/activities")

local Board = {}

local function matches(listing, search)
    if search == nil or search == "" then return true end
    local needle = search:lower()
    for _, text in ipairs({ listing.host or "", Activities.name(listing.activity) or "" }) do
        -- plain find: a search like "vorago (" mustn't be read as a pattern
        if text:lower():find(needle, 1, true) then return true end
    end
    return false
end

local function passes(listing, prefs)
  -- a set of activity keys, or nil for all
  if prefs.activities and not prefs.activities[listing.activity] then return false end
    -- a set of tags every listing must have
    for tag in pairs(prefs.tags or {}) do
        if not (listing.tags and listing.tags[tag]) then return false end
    end
    return true
end

-- sort by server timestamp
-- created is in whole seconds, so ids break ties and listings posted together keep their places
local function newer(left, right)
    if left.created ~= right.created then return left.created > right.created end
    return left.id < right.id
end

local COMPARE = {
    newest = newer,
    open_spots = function(left, right)
        local leftOpen, rightOpen = left.size - left.filled, right.size - right.filled
        if leftOpen ~= rightOpen then return leftOpen < rightOpen end
        return newer(left, right)
    end,
    activity = function(left, right)
        if left.activity ~= right.activity then return left.activity < right.activity end
        return newer(left, right)
    end,
}

-- sorted by newest (default), open_spots or activity
function Board.view(listings, prefs, search)
    prefs = prefs or {}
    local shown = {}
    for _, listing in ipairs(listings) do
        if passes(listing, prefs) and matches(listing, search) then shown[#shown + 1] = listing end
    end
    table.sort(shown, COMPARE[prefs.sort] or COMPARE.newest)
    return shown
end

return Board
