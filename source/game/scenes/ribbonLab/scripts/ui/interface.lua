local Collapsible = require('source.engine.ui.widgets.collapsible')

-- Control panel of the ribbon lab: every button cycles one property of one ribbon through a short
-- list of values, so the same panel works with a mouse and with touch.
local Interface = {}

local ROWS = 5
local ROW_HEIGHT = 46

local function label(text, value)
    if type(value) == 'boolean' then
        value = value and 'on' or 'off'
    end
    return text .. ': ' .. tostring(value)
end

-- Adds a cycle button. `values` is the list to rotate through; `apply` runs after each change.
local function cycle(ui, parent, slot, text, node, key, values, apply)
    local index = 1
    for i, value in ipairs(values) do
        if node[key] == value then
            index = i
        end
    end
    local button
    button = ui:button({
        position = { 0, 4 + (slot.column - 1) * 152, 0, 4 + (slot.row - 1) * ROW_HEIGHT },
        size = { 0, 148, 0, ROW_HEIGHT - 4 },
        text = label(text, values[index]),
        textScaled = true,
        maxTextSize = 14,
        backgroundColor = { 0.1, 0.25, 0.35 },
        onPress = function()
            index = index % #values + 1
            node[key] = values[index]
            button.text = label(text, values[index])
            if apply then
                apply(values[index])
            end
        end,
    }, parent)
    return button
end

function Interface.create(self)
    local ui = self.scene.ui
    local controls = ui:container({
        _viewportAuthored = true,
        name = 'RibbonControls',
        visible = false,
        position = { 0, 12, 0, 112 },
        size = { 0, 312, 0, ROWS * ROW_HEIGHT + 4 },
    }, ui.content)
    Collapsible.create(self.scene, controls, 'Ribbon controls')

    local function slot(row, column)
        return { row = row, column = column }
    end
    cycle(ui, controls, slot(1, 1), 'Trail width', self.single, 'width', { 0.9, 0.4, 1.6 })
    cycle(ui, controls, slot(1, 2), 'Trail life', self.single, 'lifetime', { 1.4, 0.5, 3 })
    cycle(ui, controls, slot(2, 1), 'Max length', self.single, 'maxLength', { 0, 2, 5 })
    cycle(ui, controls, slot(2, 2), 'Blade faces cam', self.dual, 'faceCamera', { false, true })
    cycle(
        ui,
        controls,
        slot(3, 1),
        'Beam texture',
        self.beam,
        'textureMode',
        { 'Wrap', 'Stretch', 'Static' }
    )
    cycle(ui, controls, slot(3, 2), 'Beam glow', self.beam, 'lightEmission', { 1, 0.5, 0 })
    cycle(ui, controls, slot(4, 1), 'Cast shadow', self.shade, 'castShadow', { true, false })
    cycle(ui, controls, slot(4, 2), 'Receive shadow', self.shade, 'receiveShadow', { true, false })
    cycle(ui, controls, slot(5, 1), 'Light influence', self.shade, 'lightInfluence', { 1, 0.5, 0 })
    ui:button({
        position = { 0, 4 + 152, 0, 4 + 4 * ROW_HEIGHT },
        size = { 0, 148, 0, ROW_HEIGHT - 4 },
        text = 'Clear trails',
        textScaled = true,
        maxTextSize = 14,
        backgroundColor = { 0.35, 0.18, 0.12 },
        onPress = function()
            self.single:clear()
            self.dual:clear()
        end,
    }, controls)
    return controls
end

return Interface
