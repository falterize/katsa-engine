local Array = require('source.engine.math.array')
local Bindings = require('source.engine.animation.bindings')
local CurveGraph = require('./curveGraph')
local Dialog = require('./dialog')
local Model = require('source.engine.editor.curves.sequenceModel')
local Timeline = require('source.engine.animation.rampTimeline')
local Sequence = require('source.engine.animation.sequence')

-- Keyframe editor for a `points` sequence (a Ramp's progress curve) or one goal track of a Ramp
-- (`property`): the curve graph, the point list, and numeric time / value fields.
local Editor = { key = 'sequence' }

function Editor.new(request)
    local target, property = request.target, request.property
    return {
        key = Editor.key,
        title = property and ('Points / ' .. property) or 'Points / normalized timeline',
        target = target,
        property = property,
        selected = 1,
        channel = 1,
        newTime = 0.5,
        status = '',
        graph = {},
        draw = Editor.draw,
    }
end

local function channelLabels(property, dimensions)
    if property and property:lower():find('color') then
        return { 'R', 'G', 'B', 'A' }
    end
    if dimensions == 4 then
        return { 'Scale X', 'Offset X', 'Scale Y', 'Offset Y' }
    end
    return { 'X', 'Y', 'Z', 'W' }
end

function Editor.draw(ig, scene, host, dialog)
    local target, property = dialog.target, dialog.property
    if target.destroyed then
        dialog.closed = true
        return
    end
    local points = property and target.bindings[property] or target.points
    if not points then
        ig.text('No timeline selected')
        return
    end
    local seconds = property and Timeline.usesSeconds(target)
    local scale = seconds and target.playbackTime or 1
    local interpolation = points.interpolation or target.interpolation or 'Linear'
    dialog.selected = math.max(1, math.min(#points, dialog.selected))

    local function touched()
        if property then
            target.goals[property] = Bindings.copy(points[#points].value)
        end
        Dialog.touch(scene)
    end

    local changed, picked = ig.combo('Interpolation', interpolation == 'Curve' and 2 or 1, { 'Linear', 'Curve' })
    if changed then
        points.interpolation = picked == 2 and 'Curve' or 'Linear'
        interpolation = points.interpolation
        touched()
    end
    ig.sameLine()
    if property then
        if ig.button('Back to goals') then
            host:openDialog('goals', { target = target })
            return
        end
    elseif ig.button('Reset 0 -> 1') then
        target.points = Sequence.linear(0, 1)
        dialog.selected = 1
        touched()
        return
    end

    local value = points[1].value
    local dimensions = Array.is(value) and #value or 1
    local labels = channelLabels(property, dimensions)
    if dimensions > 1 then
        for channel = 1, dimensions do
            if channel > 1 then
                ig.sameLine()
            end
            if ig.radio(('Plot %s##c%d'):format(labels[channel], channel), dialog.channel == channel) then
                dialog.channel = channel
            end
        end
    end
    dialog.channel = math.min(dialog.channel, dimensions)

    local width = ig.available()
    local selected, edited = CurveGraph.draw(ig, dialog.graph, points, interpolation, dialog.channel, dialog.selected, width, 190, scale)
    dialog.selected = selected
    if edited then
        touched()
    end
    ig.textDisabled('Drag points; in Curve mode drag the green handles of the selected point.')
    ig.separator()

    local point = points[dialog.selected]
    ig.text('Point %d / %d', dialog.selected, #points)
    local shown = point.time * scale
    local moved, typed = ig.dragFloat(seconds and 'Time (s)' or 'Time 0..1', shown, 0.005 * scale, 0, 0, '%.4f')
    if moved then
        Dialog.attempt(dialog, function()
            local time = typed / scale
            -- Typing a later time for the last point lengthens the animation.
            if seconds and dialog.selected == #points and time > 1 then
                Timeline.setDuration(target, math.min(typed, Timeline.MAX_DURATION + 1))
                time = 1
            end
            Model.time(points, dialog.selected, time)
            if seconds then
                Timeline.fit(target)
            end
            touched()
        end)
    end
    for channel = 1, dimensions do
        local current = Array.is(point.value) and point.value[channel] or point.value
        local label = dimensions == 1 and 'Value' or labels[channel]
        local edit, number = ig.dragFloat(label .. '##value' .. channel, current, 0.01, 0, 0, '%.4f')
        if edit and number == number and math.abs(number) < math.huge then
            if dimensions == 1 then
                point.value = number
            else
                point.value[channel] = number
            end
            touched()
        end
    end
    ig.separator()

    ig.setNextItemWidth(120)
    local timeEdit, newTime = ig.dragFloat('New point time', dialog.newTime * scale, 0.005 * scale, 0, 0, '%.3f')
    if timeEdit then
        dialog.newTime = newTime / scale
    end
    ig.sameLine()
    if ig.button('+ Add point') then
        if Dialog.attempt(dialog, function()
            dialog.selected = Model.insert(points, dialog.newTime, interpolation)
        end) then
            -- The next point goes into the longest gap.
            local longest = -1
            for i = 1, #points - 1 do
                local gap = points[i + 1].time - points[i].time
                if gap > longest then
                    longest, dialog.newTime = gap, (points[i].time + points[i + 1].time) / 2
                end
            end
            touched()
        end
    end
    -- Appends a point after the last one and lengthens the animation to reach it.
    if seconds then
        ig.sameLine()
        if ig.button('+ Add at end') then
            if Dialog.attempt(dialog, function()
                local step = math.max(0.5, target.playbackTime * 0.25)
                Timeline.setDuration(target, target.playbackTime + step)
                dialog.selected = Model.append(points)
            end) then
                touched()
            end
        end
    end
    ig.sameLine()
    if ig.button('Delete selected') then
        if Dialog.attempt(dialog, function()
            Model.remove(points, dialog.selected)
            dialog.selected = math.max(1, dialog.selected - 1)
        end) then
            touched()
        end
    end
    Dialog.status(ig, dialog)
    ig.separator()
    for index, item in ipairs(points) do
        ig.pushID(index)
        if ig.selectable(('Point %d   t = %.4f%s'):format(index, item.time * scale, seconds and ' s' or ''), index == dialog.selected) then
            dialog.selected = index
        end
        ig.popID()
    end
end

return Editor
