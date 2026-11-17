local Array = require('source.engine.math.array')
local pairs = require('source.engine.math.array').pairs
local Dialog = require('./dialog')

-- A plain table of numbers, vectors and names (`bindings` fields such as the shader layers of a
-- node): each entry is a drag field, one per vector component, or a text field for names.
local Editor = { key = 'values' }

function Editor.new(request)
    return {
        key = Editor.key,
        title = request.field.key,
        target = request.target,
        field = request.field,
        edits = {},
        status = '',
        draw = Editor.draw,
    }
end

function Editor.draw(ig, _, _, dialog)
    local target, key = dialog.target, dialog.field.key
    if target.destroyed then
        dialog.closed = true
        return
    end
    local entries = target[key]
    local names = {}
    for name in pairs(entries) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, name in ipairs(names) do
        local value = entries[name]
        ig.pushID(tostring(name))
        if Array.is(value) then
            for index, component in ipairs(value) do
                local changed, number = ig.dragFloat(('%s %d##c%d'):format(name, index, index), component, 0.01, 0, 0, '%.4g')
                if changed then
                    value[index] = number
                end
            end
        elseif type(value) == 'string' then
            local shown = dialog.edits[name] or value
            local changed, text = ig.inputText(tostring(name), shown)
            if changed then
                dialog.edits[name] = text
            end
            if ig.deactivatedAfterEdit() and dialog.edits[name] then
                local world = target._world or target._sceneWorld
                if world and not world.shaderLayers.priorities[dialog.edits[name]] then
                    dialog.status = 'Unknown shader layer'
                else
                    entries[name] = dialog.edits[name]
                    dialog.status = ''
                end
                dialog.edits[name] = nil
            end
        else
            local changed, number = ig.dragFloat(tostring(name), value, 0.01, 0, 0, '%.4g')
            if changed then
                entries[name] = number
            end
        end
        ig.popID()
    end
    Dialog.status(ig, dialog)
end

return Editor
