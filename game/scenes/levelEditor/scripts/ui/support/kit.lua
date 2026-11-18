-- Small constructors that create a widget and give it its style tags (assets/styles/editor.lua)
-- in one call, so panels do not repeat the same three lines.
local Focus = require('source.engine.ui.widgets.textFocus')

local Kit = {}

-- Resolved rectangle of a node: x, y, width, height in interface units. UI:layout() scans the
-- whole tree for changed properties, so node:getAbsolutePosition()/getAbsoluteSize() cost about a
-- millisecond each in a large UI. Per-frame polling (hover tests, drag targets) uses this instead:
-- it lays out once per editor frame (Content:update advances `_editorFrame`) and reads the fields.
function Kit.rect(node)
    local ui = node.ui
    if not ui then
        return 0, 0, 0, 0
    end
    if ui._laidOutFrame ~= ui._editorFrame then
        ui._laidOutFrame = ui._editorFrame
        ui:layout()
    end
    return node._x or 0, node._y or 0, node._width or 0, node._height or 0
end

function Kit.make(ui, class, props, parent, ...)
    local node = ui:create(class, props, parent)
    for index = 1, select('#', ...) do
        local tag = select(index, ...)
        if tag then
            node:addTag(tag)
        end
    end
    return node
end

function Kit.button(ui, parent, text, width, height, onPress, ...)
    local node = Kit.make(ui, 'Button', {
        size = { 0, width, 0, height },
        text = text,
        fontSize = 13,
    }, parent, ...)
    if onPress then
        node:connect('press', onPress)
    end
    return node
end

function Kit.label(ui, parent, text, props, ...)
    props = props or {}
    props.text, props.align = text, props.align or 'left'
    props.fontSize, props.interactable = props.fontSize or 13, false
    return Kit.make(ui, 'Label', props, parent, ...)
end

local function show(value)
    return ('%.4g'):format(value)
end

-- A TextBox that edits one number: Enter or leaving the field applies it (a bad or too small
-- value restores the old one). The second result, `refresh()`, shows an outside change unless the field is being typed in.
function Kit.numberField(ui, parent, props, get, set, minimum)
    props.fontSize = props.fontSize or 13
    props.text = show(get())
    local field = Kit.make(ui, 'TextBox', props, parent, 'field')
    local function commit()
        local value = tonumber(field.text)
        if value and value >= (minimum or -math.huge) and value == value then
            set(value)
        end
        field.text = show(get())
    end
    field:connect('submitted', commit)
    field:connect('focusLost', commit)
    local function refresh()
        if Focus.current ~= field then
            local text = show(get())
            if field.text ~= text then
                field.text = text
            end
        end
    end
    return field, refresh
end

return Kit
