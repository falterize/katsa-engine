local Loader = require('./loader')
local Systems = require('./systems')
local RootNode = require('./rootNode')
local Cleanup = require('../core.cleanup')
local World = require('../world.world')
local Renderer = require('../graphics.pipeline.renderer')
local UI = require('../ui')
local Input = require('../input.input')
local Modules = require('./modules')

-- A game scene host without the demonstration menu, tools or example behavior.
-- Scene scripts own content, systems and gameplay; the host owns engine resources.
local Host = {}
Host.__index = Host

function Host.new(manager, package, options)
    return setmetatable({
        manager = manager,
        data = manager.data,
        package = package,
        time = 0,
        showStats = false,
        runtime = 'standalone',
        options = options or {},
        statsHelp = 'F3: toggle Stats',
    }, Host)
end

-- options.prefab: the scene is loaded only to be packed (source/engine/scenes/packed): nothing is
-- drawn, so it gets no renderer or overlays, and `baseline` remembers what the host itself put into
-- the world before the scene's create script ran.
function Host:load()
    local prefab = self.options.prefab
    local profiler = self.manager.profiler
    local function mark(stage)
        if not prefab then
            profiler:markLoad(stage)
        end
    end
    if not prefab then
        profiler:beginLoad(self.package.id)
    end
    self.settings = self.package.settings
    self.zone = self.package.id
    self.resources =
        self.manager.resources:scope(Loader.manifest({}, self.settings.assets), self.package.paths)
    self.audio = self.manager.audio:scope(self.resources:scope())
    mark('Resources and audio')
    local lighting =
        Loader.configure(require('source.engine.graphics.lighting.defaults').create(), self.settings.world)
    self.world = World.new(self.resources, lighting)
    self.world.prefabs:setScene(self)
    self.root = RootNode.create(self.world)
    self.world.audio = self.audio
    self.audio.worldRoot = self.world._node
    self.camera = self.world:addCamera()
    self.renderer = not prefab and Renderer.new(self.resources) or nil
    self._ui = UI.new(1280, 720, self.resources):bindWorld(self.world)
    self._ui.parent = self.world._node
    self._ui.layoutMode = 'Viewport'
    self.input = Input.new(self)
    self.systems = Systems.new(self)
    Modules.install(self, not prefab and self.options.modules or nil)
    mark('World, renderer and UI')
    self.package:registerNodes(self.world, self.settings.nodes or {})
    require('source.engine.plugins').activate(self.world, self.settings.plugins)
    mark('Node types and plugins')
    -- A prefab runs the scene's own `main`, never the dedicated-server entry.
    self.lifecycle = require('source.engine.scenes.layout').lifecycle(
        self.package,
        prefab and 'main' or nil
    )
    if prefab then
        self.baseline = {}
        for _, node in ipairs(self.world._node:getDescendants()) do
            self.baseline[node] = true
        end
    end
    if prefab and self.lifecycle.build then
        -- A prefab scene with scripts keeps `create` for every copy and builds its content in `build`.
        self.state = self.lifecycle.build(self, self.package) or {}
    else
        self.state = assert(self.lifecycle.create(self, self.package), 'Scene create must return state')
    end
    mark('Scene create script')
    self:emit('created')
    self:resize(katsa.graphics.getDimensions())
    mark('Overlays and layout')
end

Modules.extend(Host)

function Host:createPhysics2D(options, ui)
    return require('source.engine.scenes.physics2D').create(self, options, ui)
end

function Host:createPhysics3D(options)
    assert(not self.physics, 'Scene physics is already configured')
    local merged = Loader.configure(options or {}, self.settings.physics)
    merged = Loader.configure(merged, self.options.physics)
    merged.backend = self.options.physicsBackend or merged.backend
    if merged.backend == 'auto' then
        merged.backend = nil
    end
    self.physics = self.world:createPhysics3D(merged)
    return self.physics
end

function Host:update(dt, realDt)
    local started = katsa.timer.getTime()
    local sceneDt = dt
    self.world.frameRealDelta = realDt or sceneDt
    dt = require('source.engine.world.clock').delta(self.world._node, dt)
    self.time = self.time + dt
    self.lifecycle.update2D(self.state, sceneDt, realDt or sceneDt)
    self.input:update(dt)
    self.input.actions:updateMove(0, 0, 0, 0)
    self.lifecycle.update(self.state, dt)
    self.lifecycle.update3D(self.state, dt)
    self.world:updateCameras(dt)
    self.camera = self.world.activeCamera or self.camera
    self.camera:update(katsa.graphics.getDimensions())
    self.audio:update(self.camera)
    self:emit('update', realDt or dt)
    self.updateMilliseconds = (katsa.timer.getTime() - started) * 1000
end

function Host:draw()
    if self.world.activeCamera then
        self.renderer:draw(self.world, self.camera, self.time)
        self._ui.backgroundCanvas = self.renderer.canvas
        self._ui.backgroundRenderer = self.renderer
    else
        katsa.graphics.clear(0.03, 0.04, 0.06, 1)
        self._ui.backgroundCanvas = nil
        self._ui.backgroundRenderer = nil
    end
    self:emit('beforeUI')
    local started = katsa.timer.getTime()
    self._ui:draw()
    require('source.engine.graphics.debug.orientation').draw(self)
    self.uiMilliseconds = (katsa.timer.getTime() - started) * 1000
end

function Host:resize(width, height)
    self._ui:fit(width, height)
    self.camera:update(width, height)
    self:emit('resize', width, height)
end

function Host:pointerpressed(id, x, y)
    self.input:press(id, x, y)
end

function Host:pointermoved(id, x, y, dx, dy)
    self.input:move(id, x, y, dx, dy)
end

function Host:pointerreleased(id, x, y)
    self.input:release(id, x, y)
end

function Host:pointercancelled(id)
    self.input:cancel(id)
end

function Host:keypressed(key)
    if self.pauseMenu and self.pauseMenu:keypressed(key) then
        return
    end
    if self.input:keypressed(key) then
        return
    end
    self:consume('keyUnhandled', key)
end

function Host:textinput(text)
    self.input:textinput(text)
end

function Host:keyreleased(key)
    self.input:keyreleased(key)
end

function Host:mousebutton(button, down)
    self.input:mapMouseButton(button, down)
end

function Host:wheelmoved(x, y)
    self.input:mapWheel(x, y)
    self._ui:wheel(katsa.mouse.getX(), katsa.mouse.getY(), y, x)
end

function Host:release()
    if self.released then
        return
    end
    self.released = true
    if self.pauseMenu then
        self.pauseMenu:close()
    end
    self:emit('release')
    Cleanup.run({
        function()
            if self.input then
                self.input:reset()
            end
        end,
        function()
            local state = self.state or self.package.instance
            local builds = self.options.prefab and self.lifecycle and self.lifecycle.build
            if state and self.lifecycle and not builds then
                self.lifecycle.destroy(state)
            end
        end,
        function()
            if self.systems then
                self.systems:release()
            end
        end,
        function()
            if self.world then
                self.world:release()
            end
        end,
        function()
            RootNode.release(self.root)
        end,
        function()
            if self.audio then
                self.audio:release()
            end
        end,
        function()
            if self._ui then
                self._ui:release()
            end
        end,
        function()
            if self.renderer then
                self.renderer:release()
            end
        end,
        function()
            if self.resources then
                self.resources:release()
            end
        end,
        function()
            self.package:release()
        end,
    })
end

return Host
