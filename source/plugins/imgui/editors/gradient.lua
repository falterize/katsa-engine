local Dialog = require('./dialog')

-- The colour stops of a gradient: 2..16 stops with a time (0..1, increasing), an RGB colour and a
-- transparency. The stops are edited in place; the gradient reads them each frame.
local Editor = { key = 'gradient' }

local MIN, MAX = 2, 16
local EPSILON = 0.0001

function Editor.new(request)
    return {
        key = Editor.key,
        title = 'Gradient / ' .. tostring(request.target.name or request.target.className),
        target = request.target,
        field = request.field,
        selected = 1,
        status = '',
        draw = Editor.draw,
    }
end

function Editor.draw(ig, scene, _, dialog)
    local target = dialog.target
    if target.destroyed then
        dialog.closed = true
        return
    end
    local stops = target[dialog.field.key]
    dialog.selected = math.max(1, math.min(#stops, dialog.selected))
    local function touched()
        Dialog.touch(scene)
    end
    for index, stop in ipairs(stops) do
        ig.pushID(index)
        if ig.selectable(('Stop %d'):format(index), index == dialog.selected) then
            dialog.selected = index
        end
        ig.sameLine(90)
        local previous, following = stops[index - 1], stops[index + 1]
        local low = previous and previous.time + EPSILON or 0
        local high = following and following.time - EPSILON or 1
        ig.setNextItemWidth(110)
        local moved, time = ig.dragFloat('##time', stop.time, 0.002, low, high, '%.3f')
        if moved then
            stop.time = math.max(low, math.min(high, time))
            touched()
        end
        ig.sameLine()
        ig.setNextItemWidth(160)
        local recolored, color = ig.colorEdit3('##color', stop.color)
        if recolored then
            stop.color[1], stop.color[2], stop.color[3] = color[1], color[2], color[3]
            touched()
        end
        ig.sameLine()
        ig.setNextItemWidth(120)
        local fade, transparency = ig.sliderFloat('alpha##transparency', 1 - (stop.transparency ~= nil and stop.transparency or (1 - (stop.color[4] or 1))), 0, 1)
        if fade then
            stop.transparency = 1 - transparency
            touched()
        end
        ig.popID()
    end
    ig.separator()
    if ig.button('+ Add stop') then
        Dialog.attempt(dialog, function()
            assert(#stops < MAX, 'A gradient has at most 16 stops')
            local last, before = stops[#stops], stops[#stops - 1]
            local time = (before.time + last.time) / 2
            table.insert(stops, #stops, {
                time = time,
                color = { last.color[1], last.color[2], last.color[3] },
                transparency = last.transparency,
            })
            dialog.selected = #stops - 1
            touched()
        end)
    end
    ig.sameLine()
    if ig.button('Delete selected') then
        Dialog.attempt(dialog, function()
            assert(#stops > MIN, 'A gradient needs at least two stops')
            assert(dialog.selected > 1 and dialog.selected < #stops, 'Keep the two end stops')
            table.remove(stops, dialog.selected)
            touched()
        end)
    end
    Dialog.status(ig, dialog)
end

return Editor
