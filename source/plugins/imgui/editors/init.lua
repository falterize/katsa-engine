-- ImGui versions of the property dialogs. `Editors.open(host, name, request)` opens (or
-- replaces) the dialog `name`; `Editors.draw` shows every open dialog as its own window.
local Editors = {}

local kinds = {
    sequence = require('./sequence'),
    goals = require('./goals'),
    boneMask = require('./boneMask'),
    uniforms = require('./uniforms'),
    values = require('./values'),
    gradient = require('./gradient'),
    groups = require('./groups'),
    shaderLayers = require('./shaderLayers'),
}

function Editors.open(host, name, request)
    local kind = assert(kinds[name], 'Unknown ImGui dialog: ' .. tostring(name))
    local dialog = kind.new(request or {})
    dialog.name = name
    for index, existing in ipairs(host.dialogs) do
        if existing.name == name then
            host.dialogs[index] = dialog
            return dialog
        end
    end
    host.dialogs[#host.dialogs + 1] = dialog
    return dialog
end

-- Which dialog edits a property field; nil when the field has no dialog.
function Editors.forField(target, field)
    if field.kind == 'sequence' then
        return 'sequence', { target = target }
    elseif field.kind == 'gradient' then
        return 'gradient', { target = target, field = field }
    elseif field.kind == 'bindings' then
        if target.isA and target:isA('AnimationTrack') and field.key == 'boneMask' then
            return 'boneMask', { target = target }
        elseif target.isA and target:isA('Ramp') then
            return 'goals', { target = target }
        elseif field.key == 'uniforms' and target.shaderPath then
            return 'uniforms', { target = target }
        end
        return 'values', { target = target, field = field }
    end
end

function Editors.draw(ig, scene, host)
    local index = 1
    while index <= #host.dialogs do
        local dialog = host.dialogs[index]
        local width, height = katsa.graphics.getDimensions()
        ig.setNextWindowPos(math.max(10, (width - 560) / 2), 80)
        ig.setNextWindowSize(math.min(560, width - 20), math.min(520, height - 100))
        local visible, open = ig.begin(dialog.title .. '##dialog' .. dialog.name, true)
        if visible then
            local ok, err = pcall(dialog.draw, ig, scene, host, dialog)
            if not ok then
                ig.textColored(1, 0.5, 0.4, 1, '%s', tostring(err))
            end
        end
        ig.finish()
        if not open or dialog.closed then
            table.remove(host.dialogs, index)
        else
            index = index + 1
        end
    end
end

return Editors
