-- A whole scene in an additional OS window: `window:runScene(source)` (installed on katsa windows
-- by Bootstrap) gives the window its own scene manager, world, renderer, UI and input, so a second
-- game, a tool palette or a pop-up can live next to the main scene. Everything shares the main
-- window's GL context and resources cache; only the target window differs.
local Runtime = require('../core.runtime')
local Manager = require('../core.sceneManager')

local WindowScene = {}
WindowScene.__index = WindowScene

local active = {}

local DEFAULT_FPS = 60

local function windowCall(self, fn)
    return katsa.graphics.withWindow(self.window._record, fn)
end

-- Opens `source` (a scene id, folder or package, as for the main scene) in `window`.
-- options: fps (refresh ceiling, default 60), clearColor, onClose(scene) -> false keeps it open,
-- manager (options for the scene manager).
function WindowScene.open(window, source, options)
    options = options or {}
    assert(window:isOpen(), 'The window is closed')
    assert(Runtime.createScene, 'Scene windows need the scene bootstrap')
    local manager = Manager.new(options.manager)
    manager.sceneFactory, manager.startScene = Runtime.createScene, source
    local self = setmetatable({
        window = window,
        manager = manager,
        options = options,
        interval = 1 / (options.fps or DEFAULT_FPS),
        accumulated = 0,
        clearColor = options.clearColor or { 0.03, 0.04, 0.06, 1 },
    }, WindowScene)
    window:setListener(function(name, ...)
        self:receive(name, ...)
    end)
    local scene, message
    windowCall(self, function()
        manager.focused = true
        scene, message = manager:switch(Runtime.createScene, source)
        self.width, self.height = katsa.graphics.getDimensions()
    end)
    if not scene then
        self:close()
        error('Window scene failed: ' .. tostring(message), 0)
    end
    active[#active + 1] = self
    return self
end

function WindowScene:getScene()
    return self.manager.stack[#self.manager.stack]
end

function WindowScene:isOpen()
    return not self.closed
end

-- Events of the window: pointer, wheel and keyboard go to the scene exactly like the main
-- window's events go to the main scene.
function WindowScene:receive(name, ...)
    if self.closed then
        return
    end
    local manager = self.manager
    local first, second, third, fourth = ...
    self.window:call(function()
        if name == 'mousepressed' or name == 'mousereleased' then
            if third == 1 then
                local event = name == 'mousepressed' and 'pointerpressed' or 'pointerreleased'
                manager:dispatch(event, 'mouse', first, second)
            end
        elseif name == 'mousemoved' then
            manager:dispatch('pointermoved', 'mouse', first, second, third, fourth)
        elseif name == 'wheelmoved' or name == 'keypressed' or name == 'keyreleased' then
            manager:dispatch(name, first, second, third)
        elseif name == 'textinput' then
            manager:dispatch('textinput', first)
        end
    end)
end

local function fit(self)
    local width, height = katsa.graphics.getDimensions()
    if width == self.width and height == self.height then
        return
    end
    self.width, self.height = width, height
    for _, scene in ipairs(self.manager.stack) do
        if scene.input then
            scene.input:reset()
        end
        if scene.resize then
            scene:resize(width, height)
        end
    end
end

-- One update and one frame of the scene, at most `fps` times per second.
function WindowScene:step(dt)
    if self.closed then
        return
    end
    local record = self.window._record
    if record.closeRequested then
        local keep = self.options.onClose and self.options.onClose(self) == false
        if keep then
            record.closeRequested = false
        else
            return self:close()
        end
    end
    self.accumulated = self.accumulated + dt
    if self.accumulated < self.interval or record.visible == false then
        return
    end
    local step = math.min(self.accumulated, 0.1)
    self.accumulated = 0
    local manager = self.manager
    local ok, message = pcall(function()
        katsa.graphics.drawToWindow(record, function()
            fit(self)
            manager:update(step, step)
            local color = self.clearColor
            katsa.graphics.clear(color[1], color[2], color[3], color[4])
            manager:draw()
            -- Closes the profiler's frame; without it a recording of this scene stays empty.
            manager.profiler:frame()
        end)
    end)
    if not ok then
        manager.journal:record('Window scene', message, nil, 'windowScene.step')
        katsa.log.warn('Window scene stopped: ' .. tostring(message))
        self:close()
    end
end

-- Stops the scene and closes its window.
function WindowScene:close()
    if self.closed then
        return
    end
    self.closed = true
    for index, other in ipairs(active) do
        if other == self then
            table.remove(active, index)
            break
        end
    end
    local window = self.window
    pcall(function()
        windowCall(self, function()
            self.manager:release()
        end)
    end)
    window:setListener(nil)
    if window:isOpen() then
        window:close()
    end
end

-- Called every frame by the bootstrap, after the main scene's update.
function WindowScene.updateAll(dt)
    for index = #active, 1, -1 do
        local entry = active[index]
        if entry then
            entry:step(dt)
        end
    end
end

function WindowScene.closeAll()
    for index = #active, 1, -1 do
        active[index]:close()
    end
end

-- Adds `window:runScene(source, options)` to every katsa window.
function WindowScene.install()
    local SubWindow = require('source.katsa.core.subWindow')
    function SubWindow:runScene(source, options)
        return WindowScene.open(self, source, options)
    end
end

return WindowScene
