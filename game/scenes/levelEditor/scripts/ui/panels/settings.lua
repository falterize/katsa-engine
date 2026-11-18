-- Settings window (toolbar button): Appearance (theme through the uiStyler plugin), Interface
-- (dock sizes), Snap & Grid, Camera and Shortcuts (rebind every editor InputMap action).
-- Changes apply at once and are saved to editor/settings.lua.
local InputMap = require('source.engine.input.inputMap')
local Kit = require('../kit')

local Settings = {}
Settings.__index = Settings

local CATEGORIES = { 'Appearance', 'Interface', 'Snap & Grid', 'Camera', 'Shortcuts' }
local ROW = 28
local MODIFIERS = { ['key:lctrl'] = true, ['key:rctrl'] = true, ['key:lshift'] = true, ['key:rshift'] = true, ['key:lalt'] = true, ['key:ralt'] = true }

function Settings.create(state, ui)
    local self = setmetatable({ state = state, ui = ui, widgets = {}, category = 'Appearance', open = false }, Settings)
    self.dim = Kit.make(ui, 'Button', {
        name = 'SettingsDim',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        zIndex = 50,
        visible = false,
    }, ui.content, 'dim')
    self.window = Kit.make(ui, 'Frame', {
        name = 'SettingsWindow',
        anchorPoint = { 0.5, 0.5 },
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 640, 0, 440 },
        zIndex = 51,
        visible = false,
    }, ui.content, 'window')
    Kit.label(ui, self.window, 'Editor settings', { position = { 0, 14, 0, 8 }, size = { 1, -120, 0, 24 }, fontSize = 16 }, 'title')
    local close = Kit.button(ui, self.window, 'Close', 80, 24, function()
        self:hide()
    end, 'tool')
    close.position = { 1, -92, 0, 8 }
    self.tabs = {}
    for index, name in ipairs(CATEGORIES) do
        local button = Kit.button(ui, self.window, name, 128, 26, function()
            self.category, self.dirty = name, true
        end, 'tab')
        button.position = { 0, 10, 0, 44 + (index - 1) * 30 }
        self.tabs[name] = button
    end
    self.scroll = Kit.make(ui, 'ScrollFrame', {
        position = { 0, 150, 0, 44 },
        size = { 1, -160, 1, -54 },
        canvasSize = { 0, 0, 0, 0 },
        scrollBarThickness = 6,
    }, self.window, 'list')
    self.dirty = true
    return self
end

function Settings:open_(category)
    self.category = category or self.category
    if not self.open then
        self.open = true
        self.dim.visible, self.window.visible = true, true
    end
    self.dirty = true
end

function Settings:setTheme(name)
    self.state.prefs.theme = name
    self.state.stylerNode:setTheme(name)
    self.state:savePrefs()
    self.dirty = true
end

function Settings:toggle()
    if self.open then
        self:hide()
    else
        self.open, self.dirty = true, true
        self.dim.visible, self.window.visible = true, true
    end
end

function Settings:hide()
    if self.listening then
        self.state.scene.input.map:cancelListen()
        self.listening = nil
    end
    self.open = false
    self.dim.visible, self.window.visible = false, false
    self.state:savePrefs()
end

function Settings:clear()
    for _, widget in ipairs(self.widgets) do
        if not widget.destroyed then
            widget:destroy()
        end
    end
    self.widgets = {}
end

function Settings:add(widget)
    self.widgets[#self.widgets + 1] = widget
    return widget
end

-- One labelled row: the label at the left, the control (built by `make`) at x = 250.
function Settings:row(y, label, make)
    self:add(Kit.label(self.ui, self.scroll, label, { position = { 0, 6, 0, y }, size = { 0, 240, 0, ROW - 4 } }, 'text'))
    local control = make(250, y)
    if control then
        self:add(control)
    end
    return y + ROW
end

function Settings:numberRow(y, label, get, set, minimum)
    return self:row(y, label, function(x, top)
        local box = Kit.numberField(self.ui, self.scroll, {
            position = { 0, x, 0, top },
            size = { 0, 90, 0, ROW - 6 },
        }, get, function(value)
            set(value)
            self.state:savePrefs()
        end, minimum)
        return box
    end)
end

function Settings:toggleRow(y, label, get, set)
    return self:row(y, label, function(x, top)
        local button = Kit.make(self.ui, 'Button', {
            position = { 0, x, 0, top },
            size = { 0, 90, 0, ROW - 6 },
            text = get() and 'On' or 'Off',
            fontSize = 13,
        }, self.scroll, 'tool', get() and 'on' or nil)
        button:connect('press', function()
            set(not get())
            self.state:savePrefs()
            self.dirty = true
        end)
        return button
    end)
end

function Settings:buildAppearance()
    local state, y = self.state, 0
    y = self:row(y, 'Theme', function(x, top)
        for index, name in ipairs({ 'dark', 'light' }) do
            local button = self:add(Kit.make(self.ui, 'Button', {
                position = { 0, x + (index - 1) * 94, 0, top },
                size = { 0, 90, 0, ROW - 6 },
                text = name:sub(1, 1):upper() .. name:sub(2),
                fontSize = 13,
            }, self.scroll, 'tool', state.prefs.theme == name and 'on' or nil))
            button:connect('press', function()
                self:setTheme(name)
            end)
        end
    end)
    return y
end

function Settings:buildInterface()
    local state, y = self.state, 0
    local dock = state.dock
    for _, spec in ipairs({
        { 'Left dock width', 'left' },
        { 'Right dock width', 'right' },
        { 'Bottom dock height', 'bottom' },
    }) do
        y = self:numberRow(y, spec[1], function()
            return dock.preferred[spec[2]]
        end, function(value)
            dock:setSizes({ [spec[2]] = math.floor(value) })
        end, 40)
    end
    y = self:row(y, 'Layout', function(x, top)
        local button = Kit.button(self.ui, self.scroll, 'Reset layout', 120, ROW - 6, function()
            dock:setSizes({ left = 250, right = 320, bottom = 190 })
            state:savePrefs()
        end, 'tool')
        button.position = { 0, x, 0, top }
        return button
    end)
    return self:row(y, 'Drag the borders between panels to resize them.', function() end)
end

function Settings:buildSnap()
    local state, y = self.state, 0
    y = self:toggleRow(y, 'Snap', function()
        return state.snap.enabled
    end, function(value)
        state.snap.enabled = value
    end)
    for _, spec in ipairs({
        { 'Move step (units)', 'move' },
        { 'Rotate step (degrees)', 'rotate' },
        { 'Scale step', 'scale' },
    }) do
        y = self:numberRow(y, spec[1], function()
            return state.snap[spec[2]]
        end, function(value)
            state.snap[spec[2]] = value
        end, 0.0001)
    end
    y = self:numberRow(y, 'Grid cell (units)', function()
        return state.grid.cell
    end, function(value)
        state.grid:setCell(value)
    end, 0.01)
    return self:toggleRow(y, 'Grid visible', function()
        return state.grid.visible
    end, function(value)
        state.grid:setVisible(value)
    end)
end

function Settings:buildCamera()
    local state, y = self.state, 0
    y = self:numberRow(y, 'Fly speed', function()
        return state.fly.speed
    end, function(value)
        state.fly.speed = math.max(state.fly.min, math.min(state.fly.max, value))
    end, 0.01)
    y = self:numberRow(y, 'Look sensitivity', function()
        return state.fly.sensitivity
    end, function(value)
        state.fly.sensitivity = value
    end, 0.001)
    return self:numberRow(y, 'Field of view (degrees)', function()
        return state.camera.fov
    end, function(value)
        state.camera.fov = math.max(10, math.min(150, value))
    end, 10)
end

local function title(name)
    local text = name:gsub('^editor', ''):gsub('(%u)', ' %1'):gsub('^ ', '')
    return text
end

local function defaultsOf(state, name)
    local entry = state.scene.settings.input[name]
    return entry and (entry.events or entry) or {}
end

-- Rebinding: the next pressed input becomes the action's only binding. A modifier first
-- (Ctrl, Shift, Alt) waits for a second input and makes a chord. Escape cancels.
function Settings:listen(name, button, pending)
    local map = self.state.scene.input.map
    self.listening = name
    button.text = pending and (pending .. ' + ...') or 'Press a key...'
    map:listenForEvent(function(event)
        local text = tostring(event)
        if text == 'key:escape' then
            self.listening, self.dirty = nil, true
            return
        end
        if not pending and MODIFIERS[text] then
            self:listen(name, button, text)
            return
        end
        local binding = pending and (pending .. '+' .. text) or text
        local ok, normalized = pcall(InputMap.normalize, binding)
        if ok then
            map:setEvents(name, { normalized })
            for _, other in ipairs(map:getActions()) do
                if other ~= name and other:sub(1, 6) == 'editor' then
                    for _, known in ipairs(map:getEvents(other)) do
                        if known == normalized then
                            self.state:notify(('%s is also bound to %s'):format(normalized, title(other)))
                        end
                    end
                end
            end
            self.state:savePrefs()
        else
            self.state:notify('Cannot bind ' .. binding)
        end
        self.listening, self.dirty = nil, true
    end)
end

function Settings:buildShortcuts()
    local state, y = self.state, 0
    local map = state.scene.input.map
    for _, name in ipairs(map:getActions()) do
        if name:sub(1, 6) == 'editor' then
            self:add(Kit.label(self.ui, self.scroll, title(name), { position = { 0, 6, 0, y }, size = { 0, 130, 0, ROW - 4 } }, 'text'))
            local bound = table.concat(map:getEvents(name), ', ')
            self:add(Kit.label(self.ui, self.scroll, bound, { position = { 0, 138, 0, y }, size = { 1, -300, 0, ROW - 4 } }, 'muted'))
            local rebind = self:add(Kit.button(self.ui, self.scroll, 'Rebind', 70, ROW - 6, nil, 'tool'))
            rebind.position = { 1, -156, 0, y }
            rebind:connect('press', function()
                if not self.listening then
                    self:listen(name, rebind)
                end
            end)
            local reset = self:add(Kit.button(self.ui, self.scroll, 'Reset', 60, ROW - 6, function()
                map:setEvents(name, defaultsOf(state, name))
                state:savePrefs()
                self.dirty = true
            end, 'tool'))
            reset.position = { 1, -82, 0, y }
            y = y + ROW
        end
    end
    return y
end

function Settings:rebuild()
    self:clear()
    for name, button in pairs(self.tabs) do
        if name == self.category then
            button:addTag('selected')
        else
            button:removeTag('selected')
        end
    end
    local build = ({
        Appearance = self.buildAppearance,
        Interface = self.buildInterface,
        ['Snap & Grid'] = self.buildSnap,
        Camera = self.buildCamera,
        Shortcuts = self.buildShortcuts,
    })[self.category]
    local height = build(self)
    self.scroll.canvasSize = { 0, 0, 0, height }
    self.state.styler:apply(self.window)
end

function Settings:update()
    if not self.open then
        return
    end
    local width, height = math.min(680, self.ui.width - 40), math.min(480, self.ui.height - 40)
    if width ~= self.width or height ~= self.height then
        self.width, self.height = width, height
        self.window.size = { 0, width, 0, height }
    end
    if self.dirty then
        self.dirty = false
        self:rebuild()
    end
end

return Settings
