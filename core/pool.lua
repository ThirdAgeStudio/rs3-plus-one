-- core/pool.lua: the Reaper n Chill pool as the views use it, from what the server's polls return

local Pool = {}

-- also returns a summary of what's shown, so a poll that changes nothing doesn't redraw
function Pool.mine(answer, token)
    for _, view in ipairs(answer.inPool or {}) do
        if view.token == token then
            local party = view.party or {}
            local summary = { "in", party.size or 0, party.open and "open" or "ask", tostring(view.leader) }
            for _, member in ipairs(party.members or {}) do
                summary[#summary + 1] = member.name .. (member.kills and (member.kills.done .. "/" .. member.kills.total) or "")
            end
            for _, asked in ipairs(view.requests or {}) do
                local kills = asked.kills or {}
                summary[#summary + 1] = string.format("%s %s/%s", asked.id, tostring(kills.done), tostring(kills.total))
            end
            return { token = token, party = party, leader = view.leader == true, requests = view.requests or {} },
                table.concat(summary, " ")
        end
    end
    for _, view in ipairs(answer.asked or {}) do
        if view.token == token then
            local request = view.request or {}
            return { token = token, asking = true, request = request, party = view.party },
                table.concat({ "asked", request.status or "", view.party and #(view.party.members or {}) or 0 }, " ")
        end
    end
    return nil
end

function Pool.killsLine(members)
    local parts = {}
    for _, member in ipairs(members or {}) do
        if member.kills and member.kills.total and member.kills.total > 0 then
            parts[#parts + 1] = string.format("%d/%d", member.kills.done, member.kills.total)
        end
    end
    return table.concat(parts, ", ")
end

-- the server sends the pool as changes since the plugin's pool cursor, like the board
function Pool.newCopy()
    return { byId = {}, cursor = 0 }
end

function Pool.apply(copy, answer, cursor)
    if answer.full then copy.byId = {} end
    for _, party in ipairs(answer.changed or {}) do copy.byId[party.id] = party end
    for _, id in ipairs(answer.removed or {}) do copy.byId[id] = nil end
    copy.cursor = cursor or copy.cursor
    return answer.full == true or #(answer.changed or {}) > 0 or #(answer.removed or {}) > 0
end

function Pool.list(copy)
    local parties = {}
    for _, party in pairs(copy.byId) do parties[#parties + 1] = party end
    table.sort(parties, function(left, right) return left.id < right.id end)
    return parties
end

function Pool.sections(parties, boss, ownId)
    local same, other = {}, {}
    for _, party in ipairs(parties or {}) do
        if party.id ~= ownId then
            local list = (boss and party.boss == boss) and same or other
            list[#list + 1] = party
        end
    end
    -- a party with no limit (size 0) always has room, so it sorts with the most open
    local function openSpots(party)
        if party.size == 0 then return math.huge end
        return (party.size or 0) - #(party.members or {})
    end
    local function byOpen(left, right)
        if openSpots(left) ~= openSpots(right) then return openSpots(left) > openSpots(right) end
        return left.id < right.id
    end
    table.sort(same, byOpen)
    table.sort(other, byOpen)
    return same, other
end

function Pool.onBoss(parties, boss)
    local count = 0
    for _, party in ipairs(parties or {}) do
        if party.boss == boss then count = count + #(party.members or {}) end
    end
    return count
end

return Pool
