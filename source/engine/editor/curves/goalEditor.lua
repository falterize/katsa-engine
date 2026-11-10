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
    local node = popup.ui:button({
        position = { x, 4, 0, y },
        size = { w, -8, 0, 34 },
        text = text,
        fontSize = 13,
        backgroundColor = { 0.085, 0.135, 0.19 },
    }, popup.body)
    node:connect('press', function()
        if popup.workspace.editing and not popup:commitInput() then
            return
        end
        callback()
    end)
    return node
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
                    require('source.engine.editor.curves.sequenceEditor').open(popup, item.key)
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

function Editor.open(popup)
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
            text = 'No animated properties yet. Add one, then place its points in time.',
            fontSize = 14,
        }, popup.body)
        popup.body.length = 128
        return
    end
    local Sequence = require('source.engine.animation.sequence')
    for row, key in ipairs(keys) do
        local name = key
        -- A goal is a keyframe track; one made from code with only a destination gets its track.
        if not popup.target.bindings[name] then
            popup.target.bindings[name] =
                Sequence.linear(Goals.value(popup.target, name), Copy(popup.target.goals[name]))
        end
        button(popup, name .. '  (edit points)', 0, 42 + (row - 1) * 38, 0.63, function()
            require('source.engine.editor.curves.sequenceEditor').open(popup, name)
        end)
        button(popup, 'Remove', 0.63, 42 + (row - 1) * 38, 0.37, function()
            popup.target:removeGoal(name)
            Editor.open(popup)
        end)
    end
    popup.body.length = 48 + #keys * 38
end

return Editor
