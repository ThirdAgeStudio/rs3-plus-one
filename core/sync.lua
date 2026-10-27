-- core/sync.lua: keeps the plugin's copy of the board in step with the server's poll answers

local Sync = {}

function Sync.new()
    return { byId = {}, cursor = 0, server = nil }
end

function Sync.fromServer(listing)
    local tags = {}
    for _, tag in ipairs(listing.tags or {}) do tags[tag] = true end
    listing.tags = tags
    listing.needs = listing.needs or {}
    return listing
end

-- after a restart the old cursor means nothing to the new run, so the next poll starts from 0
function Sync.apply(sync, answer)
    local restarted = sync.server ~= nil and answer.server ~= sync.server
    sync.server = answer.server
    if restarted then
        sync.cursor, sync.byId = 0, {}
        return true, true
    end
    -- a poll without the board moves no cursor, so the next one with it still gets what it missed
    local board = answer.board
    if board == nil then return false, false end
    sync.cursor = answer.cursor or sync.cursor
    local changed = board.full or #(board.changed or {}) > 0 or #(board.removed or {}) > 0
    if board.full then sync.byId = {} end
    for _, listing in ipairs(board.changed or {}) do sync.byId[listing.id] = Sync.fromServer(listing) end
    for _, id in ipairs(board.removed or {}) do sync.byId[id] = nil end
    return false, changed
end

function Sync.listings(sync, ownId)
    local list = {}
    for id, listing in pairs(sync.byId) do
        if id ~= ownId then list[#list + 1] = listing end
    end
    return list
end

function Sync.hosting(view)
    local listing = Sync.fromServer(view.listing)
    listing.members = listing.members or {}
    listing.applications = {}
    local summary = { listing.filled, #listing.needs, #listing.members }
    for _, application in ipairs(view.applications or {}) do
        if application.status == "pending" then
            listing.applications[#listing.applications + 1] = {
                id = application.id, name = application.applicant, role = table.concat(application.roles or {}, ", "),
                kills = application.kills, combat = application.combat, created = application.created,
            }
            summary[#summary + 1] = application.id
        end
    end
    return listing, table.concat(summary, " ")
end

-- a poll that changes nothing doesn't redraw
function Sync.applied(view)
    local application = view.application or {}
    local party = view.party and Sync.fromServer(view.party) or nil
    local summary = { application.status or "", party and party.filled or "", party and #(party.members or {}) or "" }
    return { status = application.status, party = party }, table.concat(summary, " ")
end

return Sync
