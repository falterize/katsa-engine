local ipairs = require('../../math.array').ipairs
local Style = require('./popupStyle')
local NodeChoices = require('../inspectors.nodeChoices')
local palette, copy = Style.palette, Style.copy
local PopupValues = {}

function PopupValues.install(Popup)
    function Popup:enum()
        self.body.length = #self.field.options * 40
        for i, option in ipairs(self.field.options) do
            do
                local node = self.ui:button({
                    position = { 0, 4, 0, (i - 1) * 40 },
                    size = { 1, -8, 0, 36 },
                    text = tostring(option),
                    fontSize = 16,
                    backgroundColor = { 0.085, 0.135, 0.19 },
                }, self.body)
                node:connect('press', function()
                    local ok, err = require('source.engine.editor.inspectors.properties').set(
                        self.workspace.scene,
                        self.target,
                        self.field,
                        option
                    )
                    if ok then
                        self:close(true)
                    else
                        self.message.text = err
                    end
                end)
            end
        end
    end

    function Popup:vectorEditor()
        local labels = self.field.labels
            or #self.field.value == 4 and { 'Scale X', 'Offset X', 'Scale Y', 'Offset Y' }
            or { 'X', 'Y', 'Z' }
        for i, value in ipairs(self.field.value) do
            local index = i
            self:input(labels[i] or tostring(i), tostring(value), (i - 1) * 42, function(text)
                local ok, err = require('source.engine.editor.inspectors.properties').set(
                    self.workspace.scene,
                    self.target,
                    self.field,
                    text,
                    index
                )
                return ok, err
            end)
        end
        self.body.length = #self.field.value * 42
    end

    function Popup:hintEditor(text)
        self.readOnlyHint = true
        local width = math.max(40, self.panel.size[2] - 40)
        local font, rasterScale = self.ui:rasterFont(16)
        local _, lines = font:getWrap(text, width / rasterScale)
        local height =
            math.max(80, #lines * font:getHeight() * font:getLineHeight() * rasterScale + 12)
        self.ui:text({
            position = { 0, 6, 0, 6 },
            size = { 1, -12, 0, height },
            text = text,
            fontSize = 16,
            align = 'left',
            padding = 0,
        }, self.body)
        self.body.length = height + 12
        for _, node in ipairs(self.panel.children) do
            if node.name == 'Confirm' then
                node.text = 'Close'
            elseif node.name == 'Cancel' then
                node.visible = false
            end
        end
    end

    function Popup:nodeEditor()
        local modelSource = self.field.key == 'geometrySource' and self.target:isA('Collider3D')
        local offset = modelSource and 44 or 0
        if modelSource then
            self:input(
                'Model path',
                type(self.target.geometrySource) == 'string' and self.target.geometrySource or '',
                0,
                function(text)
                    return require('source.engine.editor.inspectors.properties').set(
                        self.workspace.scene,
                        self.target,
                        self.field,
                        text ~= '' and text or nil
                    )
                end
            )
        end
        local rows = NodeChoices.list(self.workspace.scene, self.target, self.field)
        self.body.length = offset + #rows * 44
        for i, row in ipairs(rows) do
            do
                local node = self.ui:button({
                    position = { 0, 4, 0, offset + (i - 1) * 44 },
                    size = { 1, -8, 0, 40 },
                    text = row.label,
                    textScaled = true,
                    maxTextSize = 13,
                    backgroundColor = { 0.085, 0.135, 0.19 },
                }, self.body)
                node:connect('press', function()
                    self.workspace:cancelEdit()
                    self.focusNode, self.inputCallback = nil, nil
                    local ok, err = require('source.engine.editor.inspectors.properties').set(
                        self.workspace.scene,
                        self.target,
                        self.field,
                        row.node
                    )
                    if ok then
                        self:close(true)
                    else
                        self.message.text = err
                    end
                end)
            end
        end
    end
end

return PopupValues
