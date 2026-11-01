local Array = require('source.engine.math.array')
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Goals = require('source.engine.animation.rampGoals')
local Copy = require('source.engine.animation.bindings').copy

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
    local binding = popup.target.bindings[selected]
    local value = popup.target.goals[selected] or binding[#binding].value

    local function set(component, text)
        local number = tonumber(text)
        if not number or number ~= number or math.abs(number) == math.huge then
            return false, 'Enter a finite number'
        end
        local goal = Copy(popup.target.goals[selected] or binding[#binding].value)
        if component then
            goal[component] = number
        else
            goal = number
        end
        popup.target.goals[selected] = goal
        if binding then
            binding[#binding].value = Copy(goal)
        end
        popup.ui:invalidate()
        return true
    end
    popup.ui:text({
        position = { 0, 8, 0, y },
        size = { 1, -16, 0, 24 },
        text = selected .. ' / destination',
        fontSize = 14,
        align = 'left',
    }, popup.body)
    y = y + 28
    if Array.is(value) then
        local labels = selected:lower():find('color') and { 'R', 'G', 'B', 'A' }
            or #value == 4 and { 'Scale X', 'Offset X', 'Scale Y', 'Offset Y' }
            or { 'X', 'Y', 'Z', 'W' }
        for i, v in ipairs(value) do
            local component = i
            popup:input(labels[i], tostring(v), y, function(text)
                return set(component, text)
            end)
            y = y + 40
        end
    else
        popup:input('Value', tostring(value), y, function(text)
            return set(nil, text)
        end)
        y = y + 40
    end
    button(popup, 'Edit ' .. selected .. ' points', 0, y, 1, function()
        if not popup.target.bindings[selected] then
            popup.target.bindings[selected] = require('source.engine.animation.sequence').linear(
                Goals.value(popup.target, selected),
                Copy(popup.target.goals[selected])
            )
        end
        require('source.engine.editor.curves.sequenceEditor').open(popup, selected)
    end)
    popup.body.length = y + 44
end

return Editor
