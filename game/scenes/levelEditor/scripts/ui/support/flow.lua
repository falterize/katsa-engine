-- Left-to-right wrapping of fixed-width items (toolbar buttons, the Create palette), so nothing
-- runs off the edge of a narrow panel. Pure Lua.
local Flow = {}

-- items: list of { w = width, gap = optional extra space before the item, row = true to start
-- a new row }. Returns a list of { x, y } (same order) and the total height.
function Flow.place(items, available, gap, rowHeight, pad)
    pad = pad or 0
    local positions, x, y, rows = {}, pad, pad, 1
    for index, item in ipairs(items) do
        local before = (x > pad) and (gap + (item.gap or 0)) or 0
        if x > pad and (item.row or x + before + item.w > available - pad) then
            x, y, rows, before = pad, y + rowHeight + gap, rows + 1, 0
        end
        positions[index] = { x = x + before, y = y }
        x = x + before + item.w
    end
    return positions, rows * rowHeight + (rows - 1) * gap + 2 * pad
end

return Flow
