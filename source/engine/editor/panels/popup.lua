local Array = require('../../math.array')
local pairs = require('../../math.array').pairs
-- Modal root is a sibling of the drawer: scrolling and clipping cannot hide it.
local Popup = {}
Popup.__index = Popup
local Style = require('./popupStyle')

local copy = Style.copy

function Popup.new(workspace, field)
    local self = setmetatable({
        workspace = workspace,
        ui = workspace.ui,
        field = field,
        target = workspace.selected._editorTarget or workspace.selected,
    }, Popup)
    self.original = copy(workspace:value(field))
    self.originalField = field
    if self.target.isA and self.target:isA('Ramp') then
        self.rampSnapshot = self.target:exportData()
    end
    self.group =
        self.ui:canvasGroup({
            name = 'PropertyPopup',
            size = { 1, 0, 1, 0 },
            zIndex = 1000,
            _noOffscreen = true,
        })
    self.ui:button({
        size = { 1, 0, 1, 0 },
        text = '',
        backgroundColor = { 0, 0, 0 },
        backgroundTransparency = 0.4,
        onPress = function()
            self:close(false)
        end,
    }, self.group)
    self.panel = self.ui:container({
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 380, 0, 350 },
        anchorPoint = { 0.5, 0.5 },
        capture = true,
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, self.group)
    self.title = self.ui:text({
        position = { 0, 12, 0, 6 },
        size = { 1, -24, 0, 30 },
        text = field.key,
        fontSize = 18,
        align = 'left',
    }, self.panel)
    self.body = self.ui:scroll(
        { position = { 0, 8, 0, 42 }, size = { 1, -16, 1, -102 }, length = 300 },
        self.panel
    )
    self.message = self.ui:text({
        position = { 0, 12, 1, -58 },
        size = { 1, -24, 0, 16 },
        fontSize = 11,
        textScaled = true,
        maxTextSize = 11,
        text = '',
        align = 'left',
    }, self.panel)
    self.ui:button({
        position = { 0, 10, 1, -38 },
        size = { 0.5, -15, 0, 32 },
        name = 'Confirm',
        text = 'Apply',
        fontSize = 15,
        backgroundColor = { 0.1, 0.32, 0.45 },
        onPress = function()
            self:close(true)
        end,
    }, self.panel)
    self.ui:button({
        position = { 0.5, 5, 1, -38 },
        size = { 0.5, -15, 0, 32 },
        name = 'Cancel',
        text = 'Cancel',
        fontSize = 15,
        backgroundColor = { 0.1, 0.16, 0.23 },
        onPress = function()
            self:close(false)
        end,
    }, self.panel)
    workspace.scene.input:reset()
    self:resize()
    return self
end

function Popup:resize()
    self.panel.size = {
        0,
        math.min(self.preferredWidth or 420, self.ui.width - 24),
        0,
        math.min(self.preferredHeight or 460, self.ui.height - 24),
    }
end

function Popup:close(confirm)
    if self.closed then
        return
    end
    if confirm and self.workspace.editing then
        if not self:commitInput() then
            return
        end
    end
    if not confirm and self.rampSnapshot then
        for key, value in pairs(self.rampSnapshot) do
            self.target[key] = copy(value)
        end
        self.ui:invalidate()
    elseif not confirm and not self.readOnlyHint then
        if self.originalField.kind == 'sequence' or self.originalField.kind == 'bindings' then
            self.target[self.originalField.key] = copy(self.original)
            self.ui:invalidate()
        elseif self.originalField.kind == 'node' then
            local old = self.original
            if old and old.destroyed then
                old = nil
            end
            require('source.engine.editor.inspectors.properties').set(
                self.workspace.scene,
                self.target,
                self.originalField,
                old
            )
        elseif Array.is(self.original) then
            for i = 1, #self.original do
                require('source.engine.editor.inspectors.properties').set(
                    self.workspace.scene,
                    self.target,
                    self.originalField,
                    tostring(self.original[i]),
                    i
                )
            end
        else
            require('source.engine.editor.inspectors.properties').set(
                self.workspace.scene,
                self.target,
                self.originalField,
                self.original
            )
        end
    end
    self.closed = true
    self.workspace:cancelEdit()
    self.group:destroy()
    self.workspace.popup = nil
    self.workspace.scene.input:reset()
    if self.workspace.selected and not self.workspace.selected.destroyed then
        self.workspace:select(self.workspace.selected)
    end
end

function Popup:input(label, value, y, callback)
    self.ui:text({
        position = { 0, 6, 0, y },
        size = { 0.32, -6, 0, 34 },
        text = label,
        fontSize = 13,
        textScaled = true,
        maxTextSize = 13,
        align = 'left',
    }, self.body)
    local node
    node = self.ui:create('TextBox', {
        position = { 0.32, 0, 0, y },
        size = { 0.68, -6, 0, 34 },
        text = value,
        fontSize = 14,
        backgroundColor = { 0.085, 0.135, 0.19 },
        onPress = function()
            local ws = self.workspace
            if self.focusNode == node and ws.editing then
                return
            end
            ws._editingNode = nil
            ws.editing = { popup = true }
            ws.buffer = node.text
            node.onTextChanged = function(input)
                ws.buffer = input.text
            end
            self.focusNode, self.inputCallback = node, callback
            ws:showKeyboard()
        end,
    }, self.body)
    return node
end

function Popup:commitInput()
    if not self.inputCallback then
        return true
    end
    local ok, message = self.inputCallback(self.workspace.buffer)
    if not ok then
        self.message.text = message
        return false
    end
    if self.focusNode then
        self.focusNode.text = self.workspace.buffer
    end
    self.workspace:cancelEdit()
    self.focusNode, self.inputCallback = nil, nil
    return true
end
require('./popupValues').install(Popup)
require('./popupColor').install(Popup)
return Popup
