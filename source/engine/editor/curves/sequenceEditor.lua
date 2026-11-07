local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Model = require('./sequenceModel')
local Timeline = require('../../animation.rampTimeline')

local Editor = {}

local function clear(popup)
    popup.workspace:cancelEdit()
    popup.focusNode, popup.inputCallback = nil, nil
    while #popup.body.children > 0 do
        popup.body.children[#popup.body.children]:destroy()
    end
end

function Editor.open(popup, property)
    require('source.engine.editor.curves.curveEditor')
    clear(popup)
    popup.preferredWidth = 580
    popup.preferredHeight = 650
    popup:resize()
    local target = popup.target
    local points = property and target.bindings[property] or target.points
    if not points then
        popup.message.text = 'No timeline selected'
        return
    end
    local interpolation = points.interpolation or target.interpolation or 'Linear'
    popup.title.text = property and ('Points / ' .. property) or 'Points / normalized timeline'
    local graph

    local function commit(fn)
        local ok, err = pcall(fn)
        if not ok then
            popup.message.text = tostring(err)
            return false, tostring(err)
        end
        popup.ui:invalidate()
        return true
    end

    local function button(text, x, y, width, callback)
        return popup.ui:button({
            position = { x, 4, 0, y },
            size = { width, -8, 0, 34 },
            text = text,
            fontSize = 13,
            backgroundColor = { 0.085, 0.135, 0.19 },
            onPress = function()
                if popup.workspace.editing and not popup:commitInput() then
                    return
                end
                callback()
            end,
        }, popup.body)
    end
    local mode = button('Interpolation: ' .. interpolation, 0, 0, 0.62, function()
        points.interpolation = interpolation == 'Curve' and 'Linear' or 'Curve'
        graph.interpolation = points.interpolation
        Editor.open(popup, property)
    end)
    button(property and 'Back to Goals' or 'Reset 0 -> 1', 0.62, 0, 0.38, function()
        if property then
            require('source.engine.editor.curves.goalEditor').open(popup, property)
        else
            target.points = require('source.engine.animation.sequence').linear(0, 1)
            Editor.open(popup)
        end
    end)
    local view = require('source.engine.editor.curves.curveView').create(
        popup.ui,
        popup.body,
        target,
        property,
        points,
        interpolation,
        { width = 520, height = 170 }
    )
    graph = view.graph
    local fit, seconds = view.fit, view.seconds
    fit()
    graph.beforePointer = function()
        return not popup.workspace.editing or popup:commitInput()
    end
    popup.graph = graph

    -- Point times are stored normalized; an Animated Ramp is shown and typed in seconds.
    local function shown(time)
        return seconds and Timeline.toSeconds(target, time) or time
    end
    local function timeText(time)
        return string.format('%.4f', shown(time))
    end
    local selectedLabel = popup.ui:text({
        position = { 0, 8, 0, 280 },
        size = { 1, -16, 0, 24 },
        text = '',
        fontSize = 13,
        align = 'left',
    }, popup.body)
    local timeInput, values = {}, {}

    local function refresh()
        local point = points[graph.selected]
        selectedLabel.text =
            string.format(
                'Point %d / %d | time %s%s',
                graph.selected,
                #points,
                timeText(point.time),
                seconds and ' s' or ''
            )
        if timeInput.text then
            timeInput.text = timeText(point.time)
        end
        for i, node in ipairs(values) do
            node.text = tostring(Array.is(point.value) and point.value[i] or point.value)
        end
        fit()
        if property then
            target.goals[property] =
                require('source.engine.animation.bindings').copy(points[#points].value)
        end
        popup.ui:invalidate()
    end
    graph.onChange = refresh
    timeInput = popup:input(seconds and 'Time (s)' or 'Time 0..1', timeText(points[1].time), 308, function(text)
        local ok, err = commit(function()
            local typed = tonumber(text)
            assert(typed, 'Enter a number')
            local time = seconds and Timeline.fromSeconds(target, typed) or typed
            -- Typing a later time for the last point lengthens the animation.
            if seconds and graph.selected == #points and time > 1 then
                Timeline.setDuration(target, math.min(typed, Timeline.MAX_DURATION + 1))
                time = 1
            end
            Model.time(points, graph.selected, time)
            if seconds then
                Timeline.fit(target)
            end
        end)
        if ok then
            refresh()
        end
        return ok, err
    end)
    local slider = popup.ui:slider({
        position = { 0, 8, 0, 350 },
        size = { 1, -16, 0, 30 },
        min = 0,
        max = 1,
        value = points[1].time,
        onChange = function(v)
            local index = graph.selected
            if index == 1 or index == #points then
                return
            end
            v = math.max(
                points[index - 1].time + 0.0001,
                math.min(points[index + 1].time - 0.0001, v)
            )
            commit(function()
                Model.time(points, index, v)
            end)
            refresh()
        end,
    }, popup.body)
    local originalRefresh = refresh
    refresh = function()
        slider.value = points[graph.selected].time
        originalRefresh()
    end
    graph.onChange = refresh
    local y = 386
    local value = points[1].value
    local dimensions = Array.is(value) and #value or 1
    local labels = property and property:lower():find('color') and { 'R', 'G', 'B', 'A' }
        or dimensions == 4 and { 'Scale X', 'Offset X', 'Scale Y', 'Offset Y' }
        or { 'X', 'Y', 'Z', 'W' }
    for i = 1, dimensions do
        local channel = i
        values[i] = popup:input(
            dimensions == 1 and 'Value' or labels[i],
            tostring(Array.is(value) and value[i] or value),
            y,
            function(text)
                local v = tonumber(text)
                if not v or v ~= v or math.abs(v) == math.huge then
                    return false, 'Enter a finite number'
                end
                local point = points[graph.selected]
                if dimensions == 1 then
                    point.value = v
                else
                    point.value[channel] = v
                end
                refresh()
                return true
            end
        )
        y = y + 40
    end
    if dimensions > 1 then
        for i = 1, dimensions do
            local channel = i
            button('Plot ' .. labels[i], (i - 1) / dimensions, y, 1 / dimensions, function()
                graph.channel = channel
            end)
        end
        y = y + 40
    end
    local addTime = 0.5
    local newTimeInput = popup:input('New time', timeText(addTime), y, function(text)
        local v = tonumber(text)
        v = v and (seconds and Timeline.fromSeconds(target, v) or v)
        if not v or v <= 0 or v >= 1 then
            return false, 'Choose a time inside the animation'
        end
        addTime = v
        return true
    end)
    y = y + 42
    button('+ Add point', 0, 42, 0.34, function()
        if popup.workspace.editing and not popup:commitInput() then
            return
        end
        local ok = commit(function()
            graph.selected = Model.insert(points, addTime, interpolation)
        end)
        if ok then
            local longest = -1
            for i = 1, #points - 1 do
                local gap = points[i + 1].time - points[i].time
                if gap > longest then
                    longest = gap
                    addTime = (points[i].time + points[i + 1].time) / 2
                end
            end
            newTimeInput.text = timeText(addTime)
            refresh()
        end
    end)
    -- Appends a point after the last one and lengthens the animation to reach it.
    button('+ Add at end', 0.34, 42, 0.33, function()
        if not seconds then
            popup.message.text = 'This timeline is fixed at 0..1; add points inside it'
            return
        end
        local ok = commit(function()
            local step = math.max(0.5, target.playbackTime * 0.25)
            Timeline.setDuration(target, target.playbackTime + step)
            graph.selected = Model.append(points)
        end)
        if ok then
            refresh()
        end
    end)
    button('Delete selected', 0.67, 42, 0.33, function()
        if
            commit(function()
                Model.remove(points, graph.selected)
                graph.selected = math.max(1, graph.selected - 1)
            end)
        then
            refresh()
        end
    end)
    y = y + 42
    local pointButtons = {}

    local function list()
        for _, node in ipairs(pointButtons) do
            node:destroy()
        end
        pointButtons = {}
        for i, point in ipairs(points) do
            local index = i
            pointButtons[i] = button(
                string.format('Point %d   t = %s', i, timeText(point.time)),
                0,
                y + (i - 1) * 38,
                1,
                function()
                    graph.selected = index
                    refresh()
                end
            )
        end
        popup.body.length = y + #points * 38 + 12
    end
    local previous = graph.onChange
    graph.onChange = function()
        previous()
        list()
    end
    -- Buttons and typed edits keep the point list synchronized as well as the graph.
    local baseRefresh = refresh
    refresh = function()
        baseRefresh()
        list()
    end
    list()
    refresh()
end

function Editor.bindings(popup)
    if popup.target:isA('AnimationTrack') and popup.field.key == 'boneMask' then
        return require('source.engine.editor.inspectors.boneMaskEditor').open(popup)
    end
    if popup.target:isA('Ramp') then
        return require('source.engine.editor.curves.goalEditor').open(popup)
    end
    local row = 0
    for key, value in pairs(popup.target[popup.field.key]) do
        local name = key

        local function set(text, index)
            if type(value) == 'string' then
                local world = popup.target._world or popup.target._sceneWorld
                if not world.shaderLayers.priorities[text] then
                    return false, 'Unknown shader layer'
                end
                popup.target[popup.field.key][name] = text
                return true
            end
            local v = tonumber(text)
            if not v or v ~= v or math.abs(v) == math.huge then
                return false, 'Enter a finite number'
            end
            if index then
                popup.target[popup.field.key][name][index] = v
            else
                popup.target[popup.field.key][name] = v
            end
            return true
        end
        if Array.is(value) then
            for i, component in ipairs(value) do
                local index = i
                popup:input(name .. ' ' .. i, tostring(component), row * 40, function(text)
                    return set(text, index)
                end)
                row = row + 1
            end
        else
            popup:input(name, tostring(value), row * 40, function(text)
                return set(text)
            end)
            row = row + 1
        end
    end
    popup.body.length = row * 40
end

return Editor
