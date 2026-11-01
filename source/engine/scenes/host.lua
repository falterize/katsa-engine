local Loader = require('source.engine.scenes.loader')
local Systems = require('source.engine.scenes.systems')
local Cleanup = require('source.engine.core.cleanup')
local World = require('source.engine.world.world')
local Renderer = require('source.engine.graphics.pipeline.renderer')
local UI = require('source.engine.ui')
local Input = require('source.engine.input.input')
local Statistics = require('source.engine.debug.statistics.definitions')

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
        options = options or {},
        statsHelp = 'F3: toggle Stats',
    }, Host)
end

function Host:load()
    self.settings = self.package.settings
    self.zone = self.settings.id
    self.resources =
        self.manager.resources:scope(Loader.manifest({}, self.settings.assets), self.package.paths)
    self.audio = self.manager.audio:scope(self.resources:scope())
    local lighting =
        Loader.configure(require('source.engine.lighting.defaults').create(), self.settings.world)
    self.world = World.new(self.resources, lighting)
    self.world.audio = self.audio
    self.audio.worldRoot = self.world.root
    self.camera = self.world:addCamera()
    self.renderer = Renderer.new(self.resources)
    self.ui = UI.new(1280, 720, self.resources):bindWorld(self.world)
    self.ui.parent = self.world.root
    self.ui.layoutMode = 'Viewport'
    self.input = Input.new(self)
    self.systems = Systems.new(self)
    self.package:registerNodes(self.world, self.settings.nodes or {})
    self.lifecycle = require('source.engine.scenes.layout').lifecycle(self.package)
    self.state = assert(self.lifecycle.create(self, self.package), 'Scene create must return state')
    local layer = self.ui:container({ size = { 1, 0, 1, 0 }, zIndex = 1000 }, self.ui.content)
    self.statistics = Statistics.new(self, layer)
    self.console = require('source.engine.debug.consolePanel').new(self.ui, layer)
    self:resize(katsa.graphics.getDimensions())
end

function Host:createPhysics2D(options, ui)
    return require('source.engine.scenes.physics2D').create(self, options, ui)
end

function Host:createPhysics(options)
    assert(not self.physics, 'Scene physics is already configured')
    local merged = Loader.configure(options or {}, self.settings.physics)
    merged = Loader.configure(merged, self.options.physics)
    merged.backend = self.options.physicsBackend or merged.backend
    if merged.backend == 'auto' then
        merged.backend = nil
    end
    self.physics = self.world:createPhysics(merged)
    return self.physics
end

function Host:update(dt, realDt)
    local started = katsa.timer.getTime()
    local sceneDt = dt
    self.world.frameRealDelta = realDt or sceneDt
    dt = require('source.engine.world.clock').delta(self.world.root, dt)
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
    self.console:update()
    self.updateMilliseconds = (katsa.timer.getTime() - started) * 1000
end

function Host:draw()
    if self.world.activeCamera then
        self.renderer:draw(self.world, self.camera, self.time)
        self.ui.backgroundCanvas = self.renderer.canvas
    else
        katsa.graphics.clear(0.03, 0.04, 0.06, 1)
        self.ui.backgroundCanvas = nil
    end
    self.statistics:sample()
    local started = katsa.timer.getTime()
    self.ui:draw()
    require('source.engine.graphics.debug.orientation').draw(self)
    self.uiMilliseconds = (katsa.timer.getTime() - started) * 1000
end

function Host:resize(width, height)
    self.ui:fit(width, height)
    self.camera:update(width, height)
    if self.statistics then
        self.statistics.panel:resize()
    end
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
    if self.input:keypressed(key) then
        return
    end
    if key == 'f3' then
        self.showStats = not self.showStats
    elseif key == 'f1' then
        self.console:toggle()
    end
end

function Host:textinput(text)
    self.input:textinput(text)
end

function Host:keyreleased(key)
    self.input:keyreleased(key)
end

function Host:wheelmoved(x, y)
    self.ui:wheel(katsa.mouse.getX(), katsa.mouse.getY(), y, x)
end

function Host:release()
    if self.released then
        return
    end
    self.released = true
    if self.console then
        self.console:release()
    end
    Cleanup.run({
        function()
            if self.input then
                self.input:reset()
            end
        end,
        function()
            local state = self.state or self.package.instance
            if state and self.lifecycle then
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
            if self.audio then
                self.audio:release()
            end
        end,
        function()
            if self.ui then
                self.ui:release()
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
