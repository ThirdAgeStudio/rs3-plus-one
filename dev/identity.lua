-- dev/identity.lua: dev builds only

local Identity = {}

-- "you" becomes client username
local PLAYERS = {
    { key = "you" },
    { key = "b", name = "Player 2" },
    { key = "c", name = "Player 3" },
    { key = "d", name = "Player 4" },
}

local active = "you"
local away = {}

function Identity.active()
    return active
end

function Identity.name()
    for _, player in ipairs(PLAYERS) do
        if player.key == active then return player.name end
    end
end

function Identity.choices(character)
    local choices = {}
    for index, player in ipairs(PLAYERS) do
        choices[index] = { key = player.key, label = player.name or character or "You" }
    end
    return choices
end

function Identity.switch(net, key)
    if key == active then return end
    away[active] = net.useSlot(key ~= "you" and key or nil)
    away[key] = nil
    active = key
end

function Identity.awayTokens(net)
    local tokens = {}
    for _, held in pairs(away) do
        for _, token in ipairs(net.tokens(held)) do tokens[#tokens + 1] = token end
    end
    return tokens
end

return Identity
