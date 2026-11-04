local pairs = require('../math.array').pairs
local Tree = require('./tree.traversal')
local Properties = require('./inspectors.properties')
local utf8 = require('utf8')

local Workspace = {}
Workspace.__index = Workspace
local panelColor = { 0.035, 0.055, 0.085 }
local buttonColor = { 0.085, 0.135, 0.19 }

function Workspace.new(scene)
    local self = setmetatable({
        scene = scene,
        ui = scene.ui,
        progress = 0,
        opened = false,
        query = '',
        rows = {},
        rowPool = {},
        propertyButtons = {},
        collapsed = setmetatable({}, { __mode = 'k' }),
        categoryCollapsed = {},
    }, Workspace)
    local ui = self.ui
    self.group = ui:canvasGroup({
        name = 'WorkspaceEditor',
        size = { 1, 0, 1, 0 },
        zIndex = 100,
        _noOffscreen = true,
    })
    self.panel = ui:container({
        name = 'Workspace',
        position = { 1, 0, 0, 0 },
        size = { 0, 760, 1, 0 },
        anchorPoint = { 1, 0 },
        visible = false,
        capture = true,
        clip = true,
        backgroundColor = panelColor,
    }, self.group)
    ui:create('UICorner', { radius = { 0, 14 } }, self.panel)
    ui:text({
        position = { 0, 14, 0, 8 },
        size = { 1, -215, 0, 32 },
        text = 'Workspace',
        fontSize = 24,
        align = 'left',
        textColor = { 0.75, 0.92, 1 },
    }, self.panel)
    -- Accent line under the header.
    ui:container({
        position = { 0, 14, 0, 44 },
        size = { 0, 56, 0, 3 },
        backgroundColor = { 0.3, 0.75, 1 },
    }, self.panel)
    self.groupsButton = ui:button({
        position = { 1, -110, 0, 8 },
        size = { 0, 78, 0, 32 },
        anchorPoint = { 1, 0 },
        text = 'Groups',
        fontSize = 13,
        backgroundColor = buttonColor,
        onPress = function()
            require('source.engine.editor.panels.groupEditor').open(self)
        end,
    }, self.panel)
    self.shaderLayersButton = ui:button({
        position = { 1, -196, 0, 8 },
        size = { 0, 82, 0, 32 },
        anchorPoint = { 1, 0 },
        text = 'Shaders',
        fontSize = 12,
        backgroundColor = buttonColor,
        onPress = function()
            require('source.engine.editor.panels.shaderLayers').open(self)
        end,
    }, self.panel)
    self.close = ui:button({
        position = { 1, -12, 0, 8 },
        size = { 0, 90, 0, 32 },
        anchorPoint = { 1, 0 },
        text = 'Close',
        backgroundColor = buttonColor,
        onPress = function()
            self:toggle(false)
        end,
    }, self.panel)
    self.search = ui:button({
        position = { 0, 12, 0, 48 },
        size = { 1, -24, 0, 34 },
        text = 'Search nodes…',
        fontSize = 16,
        align = 'left',
        backgroundColor = buttonColor,
        onPress = function()
            self:beginSearch()
        end,
    }, self.panel)
    self.tree = ui:scroll({
        position = { 0, 12, 0, 94 },
        size = { 0.42, -18, 1, -174 },
        backgroundColor = {
            0.02,
            0.035,
            0.055,
        },
    }, self.panel)
    ui:create('UICorner', { radius = { 0, 10 } }, self.tree)
    self.properties = ui:scroll({
        position = { 0.42, 0, 0, 94 },
        size = { 0.58, -12, 1, -174 },
        backgroundColor = {
            0.025,
            0.04,
            0.065,
        },
    }, self.panel)
    ui:create('UICorner', { radius = { 0, 10 } }, self.properties)
    self.status = ui:text({
        position = { 0, 12, 1, -72 },
        size = { 1, -24, 0, 26 },
        fontSize = 13,
        text = 'Select a node',
        align = 'left',
        textScaled = true,
        maxTextSize = 13,
    }, self.panel)
    self.entry = ui:create('TextBox', {
        position = { 0, 12, 1, -40 },
        size = { 1, -192, 0, 32 },
        text = '',
        visible = false,
        fontSize = 16,
        align = 'left',
        backgroundColor = buttonColor,
        onTextChanged = function(node)
            self.buffer = node.text
        end,
        onPress = function()
            self:showKeyboard()
        end,
    }, self.panel)
    self.apply = ui:button({
        position = { 1, -170, 1, -40 },
        size = { 0, 76, 0, 32 },
        text = 'Apply',
        visible = false,
        fontSize = 15,
        backgroundColor = { 0.1, 0.3, 0.4 },
        onPress = function()
            self:commit()
        end,
    }, self.panel)
    self.cancel = ui:button({
        position = { 1, -88, 1, -40 },
        size = { 0, 76, 0, 32 },
        text = 'Cancel',
        visible = false,
        fontSize = 15,
        backgroundColor = buttonColor,
        onPress = function()
            self:cancelEdit()
        end,
    }, self.panel)
    self.tab = ui:button({
        name = 'WorkspaceToggle',
        position = { 1, -8, 0, 6 },
        size = { 0.2, -12, 0, 42 },
        anchorPoint = { 1, 0 },
        text = 'WS',
        fontSize = 17,
        textScaled = true,
        minTextSize = 12,
        maxTextSize = 17,
        backgroundColor = buttonColor,
        onPress = function()
            self:toggle()
        end,
    }, self.group)
    self.settingsRoot = { name = 'Debug / Input', className = 'Settings', children = {} }
    scene.controls.joystick._inputKind = 'Joystick'
    scene.controls._inputKind = 'Input'
    self.settingsRoot.children[#self.settingsRoot.children + 1] = {
        name = 'Mobile input',
        className = 'Settings',
        _editorTarget = scene.controls,
        children = {
            {
                name = 'Joystick',
                className = 'Settings',
                _editorTarget = scene.controls.joystick,
                children = {},
            },
        },
    }
    self.settingsRoot.children[#self.settingsRoot.children + 1] = {
        name = 'CPU profiler',
        className = 'Settings',
        _editorTarget = scene.manager.profiler,
        children = {},
    }
    if scene.world.particles then
        self.settingsRoot.children[#self.settingsRoot.children + 1] = {
            name = 'Particle budgets',
            className = 'Settings',
            _editorTarget = scene.world.particles,
            children = {},
        }
    end
    for _, folder in pairs(scene.world.folders) do
        self.collapsed[folder] = true
    end
    self:resize()
    self:refreshTree()
    return self
end

function Workspace:resize()
    self.panelWidth = math.min(760, self.ui.width - 16)
    self.shaderLayersButton.visible = self.ui.width >= 360
    self.panel.size = { 0, self.panelWidth, 1, 0 }
    local narrow = self.ui.width < 600
    self.tree.position = { 0, 12, 0, 94 }
    self.tree.size = narrow and { 1, -24, 0.32, 0 } or { 0.42, -18, 1, -174 }
    self.properties.position = narrow and { 0, 12, 0.32, 102 } or { 0.42, 0, 0, 94 }
    self.properties.size = narrow and { 1, -24, 0.68, -182 } or { 0.58, -12, 1, -174 }
    if self.popup then
        self.popup:resize()
    end
    self:positionPanel()
end

function Workspace:positionPanel()
    local ease = self.progress * self.progress * (3 - 2 * self.progress)
    if
        self._positionEase == ease
        and self._positionWidth == self.ui.width
        and self._positionPanelWidth == self.panelWidth
        and self._positionOpened == self.opened
    then
        return
    end
    self._positionEase, self._positionWidth = ease, self.ui.width
    self._positionPanelWidth, self._positionOpened = self.panelWidth, self.opened
    self.panel.position = { 1, (1 - ease) * self.panelWidth, 0, 0 }
    self.tab.position = { 0, math.max(46, self.ui.width - 8 - ease * self.panelWidth), 0, 6 }
    self.tab.size = { 0, self.opened and 38 or math.max(38, self.ui.width * 0.2 - 12), 0, 42 }
    -- Read-only resolved values retained for old diagnostics, never used for layout.
    self.panel.x = self.ui.width - ease * self.panelWidth
    self.panel.visible = self.progress > 0 or self.opened
end

function Workspace:toggle(value)
    self.opened = value == nil and not self.opened or value == true
    self.scene.input:reset()
    if self.scene.debugButton then
        self.scene.debugButton.visible = not self.opened
            and (not self.scene.navigation or self.scene.navigation.visible)
    end
    if self.opened then
        self:refreshTree()
    else
        if self.popup then
            self.popup:close(false)
        end
        self:cancelEdit()
    end
end
require('./tree.workspaceRows').install(Workspace)
require('./panels.workspaceEditing').install(Workspace)

function Workspace:update(dt)
    self.progress = self.opened and math.min(1, self.progress + dt / 0.25)
        or math.max(0, self.progress - dt / 0.25)
    self:positionPanel()
    if not self.opened then
        return
    end
    if
        self.selected
        and (self.selected.destroyed or self.selected.parent and self.selected.parent.destroyed)
    then
        if self.popup then
            self.popup:close(false)
        end
        self.selected = nil
        self:cancelEdit()
        self:clearInspector()
    end
    self.refreshTime = (self.refreshTime or 0) + dt
    if self.refreshTime > 0.3 then
        self.refreshTime = 0
        self:refreshTree()
    end
    self:renderRows()
    if self.selected then
        if
            not self.popup
            and self.schemaSignature
                ~= require('source.engine.editor.inspectors.schema').signature(
                    self.selected._editorTarget or self.selected
                )
        then
            self:select(self.selected, true)
        end
        if
            self.parentPathText
            and Properties.parentPath(self.selected._editorTarget or self.selected)
                ~= self.parentPathValue
        then
            self:select(self.selected, true)
        end
        self:updateValues()
    end
    if self.editing then
        self.buffer = (self.popup and self.popup.focusNode or self.entry).text
    end
end
require('./inspectors.inspector').install(Workspace)
return Workspace
