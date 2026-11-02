local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
-- Rectangular exclusion avoids modifying an ancestor's rounded stencil mask.
local Regions = {}

function Regions.subtract(regions, mask)
    local result = {}
    local mx, my, mw, mh = unpack(mask)
    for _, rect in ipairs(regions) do
        local x, y, w, h = unpack(rect)
        local left, top = math.max(x, mx), math.max(y, my)
        local right, bottom = math.min(x + w, mx + mw), math.min(y + h, my + mh)
        if right <= left or bottom <= top then
            result[#result + 1] = rect
        else
            if top > y then
                result[#result + 1] = { x, y, w, top - y }
            end
            if bottom < y + h then
                result[#result + 1] = { x, bottom, w, y + h - bottom }
            end
            if left > x then
                result[#result + 1] = { x, top, left - x, bottom - top }
            end
            if right < x + w then
                result[#result + 1] = { right, top, x + w - right, bottom - top }
            end
        end
    end
    return result
end

return Regions
