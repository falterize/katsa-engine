local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Goals = require('../../animation.rampGoals')
local Copy = require('../../animation.bindings').copy

local Editor = {}

local function clear(popup)
    popup.workspace:cancelEdit()
    popup.focusNode, popup.inputCallback = nil, nil
    while #popup.body.children > 0 do
        popup.body.children[#popup.body.children]:destroy()
    end
end

local function button(popup, text, x, y, w, callback)
    return popup.ui:button({
        position = { x, 4, 0, y },
        size = { w, -8, 0, 34 },
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

function Editor.choose(popup)
    clear(popup)
    popup.title.text = 'Add a goal property'
    button(popup, 'Back to Goals', 0, 0, 1, function()
        Editor.open(popup)
    end)
    local fields = Goals.candidates(popup.target)
    local count = 0
    for _, field in ipairs(fields) do
        if not popup.target.goals[field.key] and not popup.target.bindings[field.key] then
            count = count + 1
            local item = field
            button(popup, item.key, 0, 40 + (count - 1) * 38, 1, function()
                local ok, err = pcall(popup.target.addGoal, popup.target, item.key, item.value)
                if ok then
                    Editor.open(popup, item.key)
                else
                    popup.message.text = tostring(err)
                end
            end)
        end
    end
    if count == 0 then
        popup.message.text = 'All available numeric properties are already listed.'
    end
    popup.body.length = 44 + count * 38
end

function Editor.open(popup, selected)
    clear(popup)
    popup.preferredWidth = 560
    popup.preferredHeight = 560
    popup:resize()
    popup.title.text = 'Goals / '
        .. (popup.target:getTarget() and popup.target:getTarget().name or 'No target')
    button(popup, '+ Add goal', 0, 0, 1, function()
        Editor.choose(popup)
    end)
    local keys, seen = {}, {}
    for key in pairs(popup.target.goals) do
        keys[#keys + 1] = key
        seen[key] = true
    end
    for key in pairs(popup.target.bindings) do
        if not seen[key] then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    if #keys == 0 then
        popup.ui:text({
            position = { 0, 8, 0, 48 },
            size = { 1, -16, 0, 70 },
            text = 'No goals yet. Add a property, then set its destination or edit its timeline.',
            fontSize = 14,
        }, popup.body)
        popup.body.length = 128
        return
    end
    selected = selected or keys[1]
    local row = 0
    for _, key in ipairs(keys) do
        local name = key
        button(popup, (name == selected and '> ' or '') .. name, 0, 42 + row * 38, 0.63, function()
            Editor.open(popup, name)
        end)
        button(popup, 'Remove', 0.63, 42 + row * 38, 0.37, function()
            popup.target:removeGoal(name)
            Editor.open(popup)
        end)
        row = row + 1
    end
    local y = 48 + row * 38
    -- The binding holds the absolute values of the animation: its first point is the start and its
    -- last point the destination. Nothing is derived from the target's current value or scaled by
    -- a multiplier, so both ends are plain numbers the author types.
    local binding = popup.target.bindings[selected]
    if not binding then
        binding = require('source.engine.animation.sequence').linear(
            Goals.value(popup.target, selected),
            Copy(popup.target.goals[selected])
        )
        popup.target.bindings[selected] = binding
    end

    -- Writes one component of a binding end (index 1 = start, #binding = destination).
    local function set(end_, component, text)
        local number = tonumber(text)
        if not number or number ~= number or math.abs(number) == math.huge then
            return false, 'Enter a finite number'
        end
        local point = binding[end_]
        if component then
            point.value[component] = number
        else
            point.value = number
        end
        popup.target.goals[selected] = Copy(binding[#binding].value)
        popup.ui:invalidate()
        return true
    end
    local sample = binding[1].value
    local labels = Array.is(sample)
            and (
                selected:lower():find('color') and { 'R', 'G', 'B', 'A' }
                or #sample == 4 and { 'Scale X', 'Offset X', 'Scale Y', 'Offset Y' }
                or { 'X', 'Y', 'Z', 'W' }
            )
        or { 'Value' }
    for _, part in ipairs({ { 'Start', 1 }, { 'Destination', #binding } }) do
        local end_ = part[2]
        popup.ui:text({
            position = { 0, 8, 0, y },
            size = { 1, -16, 0, 24 },
            text = selected .. ' / ' .. part[1],
            fontSize = 14,
            align = 'left',
        }, popup.body)
        y = y + 28
        local value = binding[end_].value
        if Array.is(value) then
            for i, v in ipairs(value) do
                local component = i
                popup:input(part[1] .. ' ' .. labels[i], tostring(v), y, function(text)
                    return set(end_, component, text)
                end)
                y = y + 40
            end
        else
            popup:input(part[1], tostring(value), y, function(text)
                return set(end_, nil, text)
            end)
            y = y + 40
        end
    end
    button(popup, 'Edit ' .. selected .. ' points', 0, y, 1, function()
        require('source.engine.editor.curves.sequenceEditor').open(popup, selected)
    end)
    popup.body.length = y + 44
end

return Editor
