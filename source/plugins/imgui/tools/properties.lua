local Editors = require('../editors')
local Inspector = require('source.engine.editor.inspectors.inspector')
local NodeChoices = require('source.engine.editor.inspectors.nodeChoices')
local Properties = require('source.engine.editor.inspectors.properties')
local Schema = require('source.engine.editor.inspectors.schema')

-- Properties: the selected node's properties as their own movable window, grouped like the
-- legacy inspector (Identity, Layout / Transform, ...). Every edit goes through
-- `Properties.set`, so validation and ranges are the same as everywhere else. The curve-like
-- editors (sequence, goals, gradient, uniforms ...) open as their own windows (editors/).
local PropertiesTool = { id = 'properties', title = 'Properties' }

local CHECK = 0.3 -- seconds between structure checks (schema signature, parent path)

function PropertiesTool.new()
    return { edits = {}, status = '', checked = 0 }
end

local function targetOf(node)
    return node._editorTarget or node
end

-- Rebuilds the field list when the selection or the node's property set changed.
local function sync(state, host)
    local node = host.selection
    if node and node.destroyed then
        node, host.selection = nil, nil
    end
    local now = katsa.timer.getTime()
    if node ~= state.node then
        state.node, state.fields, state.edits, state.status = node, nil, {}, ''
    end
    if not node then
        return nil
    end
    local target = targetOf(node)
    local signature = Schema.signature(target)
    local parent = target._node and Properties.parentPath(target) or nil
    if
        not state.fields
        or now - state.checked > CHECK
            and (signature ~= state.signature or parent ~= state.parent)
    then
        state.fields = Inspector.group(Properties.list(target))
        state.signature, state.parent = signature, parent
    end
    state.checked = now
    return target
end

local function apply(scene, state, target, field, value, component)
    local ok, message = Properties.set(scene, target, field, value, component)
    state.status = ok and '' or tostring(message)
    return ok
end

local function hint(ig, field, extra)
    if ig.hovered() then
        local text = extra or field.hint or field.reason
        if text then
            ig.tooltip(text)
        end
    end
end

local function numberRow(ig, scene, state, target, field, value, component, label)
    local descriptor = Schema.descriptor(target, field.key)
    value = tonumber(value) or 0
    local magnitude = math.abs(value)
    local speed = descriptor.integer and 1 or math.max(0.005, magnitude * 0.01)
    local changed, picked = ig.dragFloat(
        label,
        value,
        speed,
        descriptor.min or 0,
        descriptor.max or 0,
        descriptor.integer and '%.0f' or '%.4g'
    )
    if changed then
        apply(scene, state, target, field, tostring(picked), component)
    end
end

local function textRow(ig, scene, state, target, field, value, label)
    local key = field.key
    local shown = state.edits[key] or tostring(value)
    ig.setNextItemWidth(-1)
    local changed, text = ig.inputText(label, shown)
    if changed then
        state.edits[key] = text
    end
    -- The text is applied when the field loses focus (Enter or a click elsewhere), so partial
    -- input such as an unfinished #shader-tag is never validated mid-typing.
    if ig.deactivatedAfterEdit() and state.edits[key] ~= nil then
        local pending = state.edits[key]
        state.edits[key] = nil
        if field.attributeNew then
            if apply(scene, state, target, field, pending) then
                state.fields = nil
            end
        else
            apply(scene, state, target, field, pending)
        end
    end
end

local function nodeRow(ig, scene, state, target, field, value, label)
    local preview = type(value) == 'string' and (value .. ' [model]')
        or value and (value.name .. ' [' .. value.className .. ']')
        or 'None'
    ig.setNextItemWidth(-1)
    if ig.beginCombo(label, preview) then
        local rows = NodeChoices.list(scene, target, field)
        for index, row in ipairs(rows) do
            ig.pushID(index)
            if ig.selectable(row.label, row.node == value and row.node ~= nil) then
                apply(scene, state, target, field, row.node)
            end
            ig.popID()
        end
        ig.endCombo()
    end
end

local DEFAULT_LABELS = {
    [2] = { 'X', 'Y' },
    [3] = { 'X', 'Y', 'Z' },
    [4] = { 'Scale X', 'Offset X', 'Scale Y', 'Offset Y' },
}

local function vectorRow(ig, scene, state, target, field, value, label)
    if field.colorMaximum then
        local maximum = field.colorMaximum
        local changed, color = ig.colorEdit3(
            label,
            { value[1] / maximum, value[2] / maximum, value[3] / maximum }
        )
        if changed then
            for component = 1, 3 do
                apply(scene, state, target, field, tostring(color[component] * maximum), component)
            end
        end
        return
    end
    local count = #value
    local labels = field.labels or DEFAULT_LABELS[count] or {}
    local width = (ig.available() - 6 * (count - 1)) / count
    for component = 1, count do
        ig.pushID(component)
        ig.setNextItemWidth(width)
        numberRow(
            ig,
            scene,
            state,
            target,
            field,
            Properties.read(target, field, component),
            component,
            '##v'
        )
        if ig.hovered() then
            ig.tooltip(labels[component] or tostring(component))
        end
        ig.popID()
        if component < count then
            ig.sameLine()
        end
    end
end

-- Kinds without an inline widget open their own dialog window (editors/).
local function dialogRow(ig, host, target, field, text)
    if ig.button(text .. '##dialog') then
        local name, request = Editors.forField(target, field)
        host:openDialog(name, request)
    end
end

local function fieldRow(ig, scene, state, host, node, target, field)
    local blocker = field.key == 'interactable' and Inspector.interactableBlocker(node)
    local labelColor = blocker and { 1, 0.72, 0.2 } or nil
    local name = blocker and (field.key .. ' !') or field.key
    ig.C.igAlignTextToFramePadding()
    if labelColor then
        ig.textColored(labelColor[1], labelColor[2], labelColor[3], 1, name)
    else
        ig.text(name)
    end
    local reason = blocker
        and ('Blocked: ancestor "%s" has Interactable off, so this node and its descendants take no input.'):format(
            tostring(blocker.name)
        )
    hint(ig, field, reason)
    ig.sameLine(130)
    ig.pushID(field.key)
    local value = Properties.read(target, field)
    local label = '##value'
    local kind = field.kind
    if field.key == 'parent' then
        ig.textDisabled(tostring(value))
    elseif field.readOnly then
        ig.textDisabled(tostring(type(value) == 'table' and field.value or value))
    elseif kind == 'boolean' then
        local changed, picked = ig.checkbox(label, value == true)
        if changed then
            apply(scene, state, target, field, picked)
        end
    elseif field.options then
        local index = 1
        for i, option in ipairs(field.options) do
            if option == value then
                index = i
            end
        end
        local items = {}
        for i, option in ipairs(field.options) do
            items[i] = tostring(option)
        end
        ig.setNextItemWidth(-1)
        local changed, picked = ig.combo(label, index, items)
        if changed then
            apply(scene, state, target, field, field.options[picked])
        end
    elseif kind == 'number' then
        ig.setNextItemWidth(-1)
        numberRow(ig, scene, state, target, field, value, nil, label)
    elseif kind == 'string' then
        textRow(ig, scene, state, target, field, value, label)
    elseif kind == 'vector' then
        vectorRow(ig, scene, state, target, field, value, label)
    elseif kind == 'node' then
        nodeRow(ig, scene, state, target, field, value, label)
    elseif kind == 'sequence' then
        dialogRow(ig, host, target, field, #value .. ' points - edit')
    elseif kind == 'bindings' then
        dialogRow(ig, host, target, field, 'Edit entries')
    elseif kind == 'gradient' then
        dialogRow(ig, host, target, field, 'Edit gradient')
    else
        ig.textDisabled(tostring(value))
    end
    ig.popID()
    if field.kind ~= 'string' then
        hint(ig, field)
    end
end

function PropertiesTool.draw(ig, scene, state, host)
    local width, height = katsa.graphics.getDimensions()
    ig.setNextWindowPos(math.max(10, width - 380), 50)
    ig.setNextWindowSize(math.min(370, width * 0.45), math.min(600, height - 70))
    local visible, open = ig.begin('Properties', true)
    if visible then
        local target = sync(state, host)
        local node = host.selection
        if not target then
            ig.textDisabled('Select a node in the Explorer.')
        else
            ig.text('%s', node.name or node.className or 'Node')
            ig.sameLine()
            ig.textDisabled(node.className or 'Settings')
            if state.status ~= '' then
                ig.textColored(1, 0.55, 0.45, 1, '%s', state.status)
            end
            ig.separator()
            if ig.beginChild('##fields', 0, 0, false) then
                for _, group in ipairs(state.fields) do
                    if ig.collapsingHeader(group.name, true) then
                        for _, field in ipairs(group.fields) do
                            -- One broken row (a throwing getter) must not take the frame down.
                            local ok, err = pcall(fieldRow, ig, scene, state, host, node, target, field)
                            if not ok then
                                ig.textColored(1, 0.5, 0.4, 1, '%s: %s', field.key, tostring(err))
                            end
                        end
                    end
                end
            end
            ig.endChild()
        end
    end
    ig.finish()
    if not open then
        host:close('properties')
    end
end

return PropertiesTool
