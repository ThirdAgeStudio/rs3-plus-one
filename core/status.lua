-- core/status.lua: what the compact view shows, worked out from the shared state

local Activities = require("core/activities")
local Reaper = require("core/reaper")

local Status = {}

local function activityName(key)
    return Activities.name(key) or "Unknown"
end

local function kills(done, total) return string.format("kills %d/%d", done, total) end

local function world(number)
    return "World " .. tostring(math.tointeger(number) or number or "?")
end

function Status.compact(state)
    local listing, pool, application = state.listing, state.pool, state.application
    local applications = listing and listing.applications or {}
    local requests = pool and pool.leader and pool.requests or {}

    -- waiting > newest > rest
    local waiting = {}
    for _, applicant in ipairs(applications) do
        waiting[#waiting + 1] = {
            kind = "application", id = applicant.id, created = applicant.created,
            text = string.format("%s applied (%s)", applicant.name, applicant.role),
        }
    end
    for _, request in ipairs(requests) do
        waiting[#waiting + 1] = {
            kind = "request", id = request.id, created = request.created,
            text = request.kills and request.kills.total > 0
                and string.format("%s wants to join (%s)", request.name, kills(request.kills.done, request.kills.total))
                or string.format("%s wants to join", request.name),
        }
    end
    table.sort(waiting, function(left, right) return left.created > right.created end)

    local status = { more = math.max(0, #waiting - 1), notice = state.notice }
    if waiting[1] then
        status.ask = { kind = waiting[1].kind, id = waiting[1].id, text = waiting[1].text }
    end

    if listing then
        status.kind = "hosting"
        status.title = string.format("%s %d/%d, %s", activityName(listing.activity), listing.filled, listing.size,
            world(listing.world))
        local needs = listing.needs or {}
        status.detail = #needs > 0 and "Needs " .. table.concat(needs, ", ") or "Full"
        status.actions = { "close_listing" }
    elseif pool and pool.asking then
        status.kind = "pool_asking"
        local party = pool.party
        status.title = party and string.format("Asked to join %s, %s", Reaper.bossName(party.boss), world(party.world))
            or "Asked to join a Reaper party"
        status.detail = pool.request and pool.request.status == "declined" and "Declined by the leader" or "Waiting on the leader"
        status.actions = { "pool_leave" }
    elseif pool then
        local party = pool.party or {}
        local members = #(party.members or {})
        status.kind = "pool"
        status.title = (party.size or 0) > 0
            and string.format("%s %d/%d, %s", Reaper.bossName(party.boss), members, party.size, world(party.world))
            or string.format("%s, %d in, %s", Reaper.bossName(party.boss), members, world(party.world))
        status.detail = members > 1 and string.format("Party of %d: head to %s", members, world(party.world))
            or "Solo in the pool"
        status.actions = { "pool_leave" }
    elseif application then
        status.kind = "applied"
        status.title = string.format("Applied to %s, %s", activityName(application.activity), world(application.world))
        if application.status == "accepted" then
            status.detail = "Accepted: head to " .. world(application.world)
            status.actions = { "withdraw" }
        elseif application.status == "declined" then
            status.detail = "Declined by the host"
            status.actions = { "dismiss" }
        else
            status.detail = "Waiting on " .. (application.host or "the host")
            status.actions = { "withdraw" }
        end
    else
        status.kind = "idle"
        status.title = "Not in a party"
        status.actions = { "browse", "join_pool" }
    end
    return status
end

return Status
