-- core/json.lua: JSON for talking to the server

local Json = {}

local ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encodeString(text)
    return '"' .. text:gsub('[%c"\\]', function(char)
        return ESCAPES[char] or string.format("\\u%04x", char:byte())
    end) .. '"'
end

local function isArray(value)
    local count = 0
    for key in pairs(value) do
        if math.type(key) ~= "integer" or key < 1 then return false end
        count = count + 1
    end
    return count == #value
end

local encode

local function encodeTable(value)
    local parts = {}
    if next(value) == nil or isArray(value) then
        for index = 1, #value do parts[index] = encode(value[index]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local item = value[key]
        if item == nil then item = value[tonumber(key)] end
        parts[#parts + 1] = encodeString(key) .. ":" .. encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encode = function(value)
    local kind = type(value)
    if value == nil then return "null" end
    if kind == "boolean" then return tostring(value) end
    if kind == "string" then return encodeString(value) end
    if kind == "table" then return encodeTable(value) end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then error("json: can't encode " .. value) end
        if math.type(value) == "integer" then return tostring(value) end
        return string.format("%.17g", value)
    end
    error("json: can't encode a " .. kind)
end

Json.encode = encode

local function skip(text, position)
    return text:find("[^ \t\r\n]", position) or #text + 1
end

local function fail(text, position, what)
    error(string.format("json: %s at %d near %q", what, position, text:sub(position, position + 10)), 0)
end

local decodeValue

local function decodeString(text, position)
    local parts, start = {}, position + 1
    while true do
        local special = text:find('["\\]', start)
        if not special then fail(text, position, "unfinished string") end
        parts[#parts + 1] = text:sub(start, special - 1)
        if text:sub(special, special) == '"' then return table.concat(parts), special + 1 end
        local escape = text:sub(special + 1, special + 1)
        if escape == "u" then
            local code = tonumber(text:sub(special + 2, special + 5), 16)
            if not code then fail(text, special, "bad \\u escape") end
            start = special + 6
            -- characters outside the basic plane come as surrogates
            if code >= 0xD800 and code <= 0xDBFF and text:sub(start, start + 1) == "\\u" then
                local low = tonumber(text:sub(start + 2, start + 5), 16)
                if low and low >= 0xDC00 and low <= 0xDFFF then
                    code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                    start = start + 6
                end
            end
            parts[#parts + 1] = utf8.char(code)
        else
            local plain = ({ b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" })[escape] or escape
            if not plain:find('^["\\/\b\f\n\r\t]$') then fail(text, special, "bad escape") end
            parts[#parts + 1] = plain
            start = special + 2
        end
    end
end

local function decodeNumber(text, position)
    local literal = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
    local value = literal and tonumber(literal)
    if not value then fail(text, position, "bad number") end
    return value, position + #literal
end

local function decodeArray(text, position)
    local result = {}
    position = skip(text, position + 1)
    if text:sub(position, position) == "]" then return result, position + 1 end
    while true do
        local value
        value, position = decodeValue(text, position)
        result[#result + 1] = value
        position = skip(text, position)
        local char = text:sub(position, position)
        if char == "]" then return result, position + 1 end
        if char ~= "," then fail(text, position, "expected , or ]") end
        position = skip(text, position + 1)
    end
end

local function decodeObject(text, position)
    local result = {}
    position = skip(text, position + 1)
    if text:sub(position, position) == "}" then return result, position + 1 end
    while true do
        if text:sub(position, position) ~= '"' then fail(text, position, "expected a key") end
        local key
        key, position = decodeString(text, position)
        position = skip(text, position)
        if text:sub(position, position) ~= ":" then fail(text, position, "expected :") end
        result[key], position = decodeValue(text, skip(text, position + 1))
        position = skip(text, position)
        local char = text:sub(position, position)
        if char == "}" then return result, position + 1 end
        if char ~= "," then fail(text, position, "expected , or }") end
        position = skip(text, position + 1)
    end
end

local LITERALS = { ["true"] = true, ["false"] = false }

decodeValue = function(text, position)
    position = skip(text, position)
    local char = text:sub(position, position)
    if char == "{" then return decodeObject(text, position) end
    if char == "[" then return decodeArray(text, position) end
    if char == '"' then return decodeString(text, position) end
    if char == "-" or char:find("%d") then return decodeNumber(text, position) end
    for word, value in pairs(LITERALS) do
        if text:sub(position, position + #word - 1) == word then return value, position + #word end
    end
    if text:sub(position, position + 3) == "null" then return nil, position + 4 end
    fail(text, position, "unexpected character")
end

function Json.decode(text)
    local value, position = decodeValue(text, 1)
    if skip(text, position) <= #text then fail(text, position, "trailing text") end
    return value
end

return Json
