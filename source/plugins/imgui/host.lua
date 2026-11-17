local Backend = require('./backend')
local Layers = require('./layers')
local ControlPanels = require('./controlPanels')
local Editors = require('./editors')
local Toolbar = require('./toolbar')
local Tools = require('./tools')

-- The ImGui side of a scene: owns the context, draws the engine's tool windows and every
-- ImGuiLayer of the scene's world, and sits between the scene's input events and ImGui.
--
--   local host, reason = Host.attach(scene)   -- nil, reason without the native library
--   host:frame(dt); host:draw()               -- each frame, after the scene and its UI
--   host:keypressed(key) ...                  -- event hooks: true means ImGui took the event
local Host = {}
Host.__index = Host

function Host.attach(scene, options)
    local backend, reason = Backend.new(options)
    if not backend then
        return nil, reason
    end
    local self = setmetatable({
        scene = scene,
        backend = backend,
        open = {},
        state = {},
        menuVisible = false,
        dialogs = {},
    }, Host)
    for _, tool in ipairs(Tools) do
        self.state[tool.id] = tool.new()
    end
    return self
end

local function isOpen(self, tool)
    -- The Stats window shares the scene's own `showStats` switch (F3, the Stats button).
    if tool.id == 'stats' then
        return self.scene.showStats == true
    end
    return self.open[tool.id] == true
end

-- Whether a tool window is open (Stats shares the scene's own switch).
function Host:isOpen(id)
    if id == 'stats' then
        return self.scene.showStats == true
    end
    return self.open[id] == true
end

function Host:toggle(id)
    if id == 'stats' then
        self.scene.showStats = not self.scene.showStats
    else
        self.open[id] = not self.open[id]
    end
end

function Host:close(id)
    if id == 'stats' then
        self.scene.showStats = false
    else
        self.open[id] = false
    end
end

-- Opens a property dialog (sequence, goals, uniforms, gradient, groups, shaderLayers ...) as its
-- own window; opening the same kind again replaces it.
function Host:openDialog(name, request)
    return Editors.open(self, name, request)
end

function Host:build(ig)
    Toolbar.draw(ig, self.scene, self)
    ControlPanels.draw(ig, self.scene, self)
    Editors.draw(ig, self.scene, self)
    if self.menuVisible and ig.beginMainMenuBar() then
        if ig.beginMenu('Tools') then
            for _, tool in ipairs(Tools) do
                if ig.menuItem(tool.title, tool.key and tool.key:upper() or nil, isOpen(self, tool)) then
                    self:toggle(tool.id)
                end
            end
            ig.endMenu()
        end
        ig.endMainMenuBar()
    end
    for _, tool in ipairs(Tools) do
        if isOpen(self, tool) then
            tool.draw(ig, self.scene, self.state[tool.id], self)
        end
    end
    for layer in pairs(Layers) do
        if layer._sceneWorld == self.scene.world and not layer.destroyed then
            layer:draw(self.backend)
        end
    end
end

function Host:frame(dt)
    self.backend:sync()
    self.backend:frame(dt, function(ig)
        self:build(ig)
    end)
end

function Host:draw()
    self.backend:draw()
end

-- Tool hotkeys; F10 shows the Tools menu bar. Returns true when the key was used.
function Host:keypressed(key)
    local captured = self.backend:key(key, true)
    if captured then
        return true
    end
    -- The scene's own menu key (InputMap / Input.menuKey) keeps priority over tool hotkeys.
    local input = self.scene.input
    if input and input.menuKey == key then
        return false
    end
    if key == 'f10' then
        self.menuVisible = not self.menuVisible
        return true
    end
    for _, tool in ipairs(Tools) do
        if tool.key == key then
            self:toggle(tool.id)
            return true
        end
    end
    return false
end

function Host:keyreleased(key)
    self.backend:key(key, false)
end

for _, name in ipairs({ 'pointerpressed', 'pointermoved', 'pointerreleased', 'mousebutton', 'wheelmoved', 'textinput' }) do
    Host[name] = function(self, ...)
        return self.backend[name](self.backend, ...)
    end
end

function Host:release()
    self.backend:release()
end

return Host
