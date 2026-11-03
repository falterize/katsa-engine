local unpack = require('../math.array').unpack
local ipairs = require('../math.array').ipairs
local Time = require('./time')
local Audio = require('../audio')
local Data = require('../persistence.data')

local Manager = {}
Manager.__index = Manager

function Manager.new(options)
    options = options or {}
    local clock = Time.new()
    local resources = require('source.engine.core.resources').new(options.manifest)
    local journal = require('source.engine.debug.journal').new()
    resources.store.journal = journal
    return setmetatable({
        stack = {},
        focused = true,
        frameDelta = 0,
        frameTime = 0,
        time = clock,
        journal = journal,
        profiler = require('source.engine.debug.profiler').new(),
        resources = resources,
        data = Data.new(),
        audio = Audio.new({ clock = clock, resources = resources:scope() }),
    }, Manager)
end

local function dispose(scene)
    require('source.engine.core.cleanup').run({
        function()
            if scene.input then
                scene.input:reset()
            end
        end,
        function()
            if scene.exit then
                scene:exit()
            end
        end,
        function()
            if scene.release then
                scene:release()
            end
        end,
    })
end

function Manager:prepare(factory, ...)
    assert(not self._transitioning, 'Scene transitions are not reentrant')
    self._transitioning = true
    local arguments = { ... }
    local argumentCount = select('#', ...)
    local scene
    local ok, err = pcall(function()
        scene = factory(self, unpack(arguments, 1, argumentCount))
        if scene.load then
            scene:load()
        end
        if scene.enter then
            scene:enter()
        end
    end)
    self._transitioning = false
    if not ok then
        if scene and scene.release then
            pcall(scene.release, scene)
        end
        self.lastSceneError = tostring(err)
        error('Scene load failed: ' .. tostring(err), 0)
    end
    return scene
end

function Manager:push(factory, ...)
    if self._busy then
        self.pendingPush = { factory = factory, args = { ... } }
        return
    end
    local ok, scene = pcall(self.prepare, self, factory, ...)
    if not ok then
        self:reportError(scene)
        return nil, scene
    end
    local old = self.stack[#self.stack]
    if old and old.pause then
        old:pause()
    end
    if old and old.input then
        old.input:reset()
    end
    self.stack[#self.stack + 1] = scene
    return scene
end

function Manager:pop()
    if self._busy then
        self.pendingPop = true
        return
    end
    local scene = table.remove(self.stack)
    if scene then
        local ok, err = pcall(dispose, scene)
        if not ok then
            self:reportError(err)
        end
        if jit then
            jit.flush()
        end
    end
    local old = self.stack[#self.stack]
    if old and old.resume then
        old:resume()
    end
end

function Manager:switch(factory, ...)
    if self._busy then
        self:requestSwitch(factory, ...)
        return nil
    end
    local ok, scene = pcall(self.prepare, self, factory, ...)
    if not ok then
        self:reportError(scene)
        return nil, scene
    end
    self.pendingSwitch = nil
    local old = self.stack
    self.stack = { scene }
    local actions = {}
    for i = #old, 1, -1 do
        local previous = old[i]
        actions[#actions + 1] = function()
            dispose(previous)
        end
    end
    local released, err = pcall(require('source.engine.core.cleanup').run, actions)
    if not released then
        self:reportError(err)
    end
    -- Traces can embed constants from scene-owned closures even when their
    -- roots belong to shared engine functions. Retire that code generation
    -- after replacing a scene; ordinary frames never clear the JIT cache.
    if #old > 0 and jit then
        jit.flush()
    end
    return scene
end

function Manager:preload(items)
    return self.resources:preload(items)
end
-- Contact callbacks may request a transition, but never destroy a world while its solver is
-- running.
function Manager:requestSwitch(factory, ...)
    self.pendingSwitch = { factory = factory, arguments = { ... } }
end

-- Whether the top scene keeps its full update while the window is unfocused or minimised. The
-- debug menu sets `backgroundOverride` (true/false) for the current run; otherwise the scene's
-- `runInBackground` setting decides (default false).
function Manager:runsInBackground()
    if self.backgroundOverride ~= nil then
        return self.backgroundOverride
    end
    local scene = self.stack[#self.stack]
    return scene ~= nil and scene.settings ~= nil and scene.settings.runInBackground == true
end

function Manager:update(dt, realDt)
    if self.drawFinishedAt then
        self.frameGapMilliseconds = (katsa.timer.getTime() - self.drawFinishedAt) * 1000
    end
    -- Diagnostics retain full wall delta even when the caller clamps simulation dt.
    local frameDelta = realDt or dt
    assert(
        type(frameDelta) == 'number' and frameDelta >= 0 and frameDelta < math.huge,
        'Frame delta must be finite and non-negative'
    )
    self.frameDelta = frameDelta
    self.frameTime = self.frameTime + frameDelta
    local scene = self.stack[#self.stack]
    if scene and (self.focused or self:runsInBackground()) and scene.update then
        self._busy = true
        local ok, err =
            pcall(scene.update, scene, self.time:update(dt, scene.simulation == false), dt)
        self._busy = false
        if not ok then
            self.journal:record('Scene update', err, nil, 'scene.update')
            error(err, 0)
        end
    elseif scene and not self.focused and scene.updateInBackground then
        -- An unfocused or minimised window freezes its scene. A scene that must keep serving
        -- something (a hosted game answering the network) does that work here instead.
        self._busy = true
        local ok, err = pcall(
            scene.updateInBackground,
            scene,
            -- Same scaled step as a focused update, so the debug timeScale still applies.
            self.time:update(dt, scene.simulation == false),
            dt
        )
        self._busy = false
        if not ok then
            self.journal:record('Scene background update', err, nil, 'scene.updateInBackground')
            error(err, 0)
        end
    end
    self:flushTransitions()
end

function Manager:draw()
    for _, scene in ipairs(self.stack) do
        if scene.draw then
            scene:draw()
        end
    end
    self.drawFinishedAt = katsa.timer.getTime()
end

function Manager:dispatch(event, ...)
    local scene = self.stack[#self.stack]
    if scene and scene[event] then
        self._busy = true
        local ok, result = pcall(scene[event], scene, ...)
        self._busy = false
        if not ok then
            error(result, 0)
        end
        self:flushTransitions()
        return result
    end
end

function Manager:flushTransitions()
    local pending = self.pendingSwitch
    if pending then
        self.pendingSwitch, self.pendingPop, self.pendingPush = nil, nil, nil
        self:switch(pending.factory, unpack(pending.arguments))
    elseif self.pendingPop then
        self.pendingPop = nil
        self:pop()
    elseif self.pendingPush then
        local push = self.pendingPush
        self.pendingPush = nil
        self:push(push.factory, unpack(push.args))
    end
end

function Manager:focus(focused)
    self.focused = focused
    for _, scene in ipairs(self.stack) do
        if focused and scene.world then
            scene.world:invalidateRender()
            for _, node in ipairs(scene.world.root:getDescendants()) do
                if node._worldBoundary and node._world and node._world.invalidateRender then
                    node._world:invalidateRender()
                end
            end
        end
        if scene.input then
            scene.input:reset()
        end
    end
    local top = self.stack[#self.stack]
    if top and top.audio then
        if focused or self:runsInBackground() then
            top.audio:resume()
        else
            top.audio:pause()
        end
    end
end

function Manager:reportError(message)
    self.journal:record('Scene', message, nil, 'sceneManager')
    self.lastSceneError = tostring(message)
    self.errors = self.errors or {}
    self.errors[#self.errors + 1] = { system = 'Scene', message = self.lastSceneError }
    if #self.errors > 20 then
        table.remove(self.errors, 1)
    end
    local scene = self.stack[#self.stack]
    if
        scene
        and scene.ui
        and not scene.ui.released
        and scene.ui.overlays
        and not scene.ui.overlays.destroyed
    then
        scene.sceneErrorLabel = scene.sceneErrorLabel
            or scene.ui:text({
                position = { 0, 12, 0, 58 },
                size = { 1, -24, 0, 42 },
                textScaled = true,
                maxTextSize = 13,
                backgroundColor = { 0.3, 0.04, 0.04 },
                textColor = { 1, 0.8, 0.7 },
                zIndex = 500,
            }, scene.ui.overlays)
        scene.sceneErrorLabel.text = self.lastSceneError
    end
end

function Manager:release()
    local stack = self.stack
    self.stack = {}
    local actions = {}
    for i = #stack, 1, -1 do
        local scene = stack[i]
        actions[#actions + 1] = function()
            dispose(scene)
        end
    end
    actions[#actions + 1] = function()
        self.audio:release()
    end
    actions[#actions + 1] = function()
        self.resources:release()
    end
    require('source.engine.core.cleanup').run(actions)
end

return Manager
