-- core/pager.lua
-- the page asked for is clamped, since listings closing between polls can leave it past the end

local Pager = {}

function Pager.page(items, perPage, page)
    local pages = math.max(1, math.ceil(#items / perPage))
    page = math.max(1, math.min(pages, math.floor(page or 1)))
    local shown = {}
    for index = (page - 1) * perPage + 1, math.min(#items, page * perPage) do
        shown[#shown + 1] = items[index]
    end
    return shown, page, pages
end

return Pager
