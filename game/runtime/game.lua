local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Loader = require('source.engine.scenes.loader')
local Systems = require('source.engine.scenes.systems')
local World3D = require('source.engine.world.world')
local Renderer = require('source.engine.graphics.pipeline.renderer')
local UI = require('source.engine.ui')
local Input = require('source.engine.input.input')
local Modules = require('source.engine.scenes.modules')

local Game = {}
Game.__index = Game

function Game.new(manager, zone, sampleType, options)
    if type(sampleType) == 'table' then
        options, sampleType = sampleType, sampleType.sampleType
    end
    options = options or {}
    assert(
        options.physicsBackend == nil
            or options.physicsBackend == 'jolt'
            or options.physicsBackend == 'oimo'
            or options.physicsBackend == 'auto',
        'Scene physicsBackend must be jolt, oimo or auto'
    )
    return setmetatable({
        manager = manager,
        data = manager.data,
        zone = zone or 'original',
        sampleType = sampleType,
        options = options,
        time = 0,
        demoAnimations = false,
        billboardMotion = true,
        billboardsVisible = true,
        showStats = false,
        runtime = 'game',
    }, Game)
end

function Game:createPhysics3D(settings)
    assert(not self.physics, 'Scene physics is already configured')
    local merged = {}
    for key, value in pairs(settings or {}) do
        merged[key] = value
    end
    for key, value in pairs(self.settings.physics or {}) do
        merged[key] = value
    end
    for key, value in pairs(self.options.physics or {}) do
        merged[key] = value
    end
    merged.backend = self.options.physicsBackend or merged.backend
    if merged.backend == 'auto' then
        merged.backend = nil
    end
    self.physics = self.world:createPhysics3D(merged)
    return self.physics
end

function Game:load()
    local profiler = self.manager.profiler
    profiler:beginLoad(self.options.package or self.zone)
    self.package = self.options._package
        or Loader.open(
            self.options.package or self.zone,
            require('game.sceneCatalog'),
            require('game.data.assetRoots').shared
        )
    self.settings = self.package.settings
    self.zone = self.package.id
    local manifest = Loader.manifest({}, self.settings.assets)
    self.resources = self.manager.resources:scope(manifest, self.package.paths)
    self.audio = self.manager.audio:scope(self.resources:scope())
    profiler:markLoad('Open package, resources and audio')
    local environment =
        Loader.configure(require('game.data.settings').create(), self.settings.world)
    self.world = World3D.new(self.resources, environment)
    self.world.prefabs:setScene(self)
    -- The top node: the main World3D (World2D inside it) and the storage containers hang from it.
    self.root = require('source.engine.scenes.rootNode').create(self.world)
    self.systems = Systems.new(self)
    self.world.audio = self.audio
    self.audio.worldRoot = self.world._node
    self.camera = self.world:addCamera()
    self.renderer = Renderer.new(self.resources)
    self._ui = UI.new(1280, 720, self.resources):bindWorld(self.world)
    self._ui.parent = self.world._node
    self._ui.name = 'World2D'
    -- Reference layout is converted to viewport fractions after construction.
    self._ui.layoutMode = 'Fit'
    -- Scene-owned mobile layout. One pointer stays assigned until release.
    self.controls = {
        joystick = { x = 125, y = 570, radius = 88 },
        camera = { x = 0, y = 138, width = 1280, height = 582 },
        speed = 75,
        verticalSpeed = 50,
        sensitivity = 0.1,
    }
    self._ui.content.name = 'GameHUD'
    self._ui.overlays = self._ui:canvasGroup({
        position = { 0, 0, 0, 0 },
        size = { 0, 1280, 0, 720 },
        name = 'Overlays',
        zIndex = 50,
    })
    self.input = Input.new(self, self.controls)
    Modules.install(self, self.options.modules or require('game.runtime.modules').game)
    -- Default Esc menu; a scene's main.lua calls attach(scene, true) to keep time running.
    require('game.runtime.pauseMenu').attach(self)
    profiler:markLoad('World, renderer and UI')
    self.package:registerNodes(self.world, self.settings.nodes or {})
    require('source.engine.plugins').activate(self.world, self.settings.plugins)
    profiler:markLoad('Node types and plugins')
    self.demo = Loader.create(self)
    profiler:markLoad('Scene create script')
    self:emit('created')
    self._ui:adaptReference(1280, 720)
    self:emit('ready')
    self:resize(katsa.graphics.getDimensions())
    if self.sampleType then
        require('game.scenes.nodeCatalog.scripts.catalog.samples').prepare(
            self,
            self.sampleType
        )
    end
end

-- Called explicitly by main.create between content construction and private UI.
function Game:preparePresentation()
    if self.character then
        self.world:setInteractionSource(self.character.body.node)
    end
    self:buildUI()
    self:emit('presentation')
end

function Game:enter()
    self.camera:update(katsa.graphics.getDimensions())
end

function Game:resize(w, h)
    self._ui:fit(w, h)
    if self.controls then
        local vw, vh = self._ui.width, self._ui.height
        if not self.controls.joystick.custom and not self.controls.joystick.relocated then
            self.controls.joystick.x = vw * 125 / 1280
            self.controls.joystick.y = vh * 570 / 720
            self.controls.joystick.radius = math.min(vw / 1280, vh / 720) * 88
        else
            local j = self.controls.joystick
            j.radius = math.min(j.radius, math.min(vw, vh) / 2)
            j.x = math.max(j.radius, math.min(vw - j.radius, j.x))
            j.y = math.max(j.radius, math.min(vh - j.radius, j.y))
        end
        self.controls.camera = { x = 0, y = vh * 138 / 720, width = vw, height = vh * 582 / 720 }
    end
    self:emit('resize', w, h)
    if self.demo and self.demo.toolbar then
        self.demo.toolbar.size = { 0, math.min(340, self._ui.width - 24), 0.45, -24 }
    end
    if self.stressMotion then
        self.stressMotion:resize()
    end
    self.camera:update(w, h)
end

function Game:pointerpressed(id, x, y)
    if self:consume('pointerpressed', id, x, y) then
        return
    end
    local demo = self.demo
    if demo and demo.pointerpressed then
        demo:pointerpressed(id, x, y)
    end
    self.input:press(id, x, y)
end

function Game:pointermoved(id, x, y, dx, dy)
    if self:consume('pointermoved', id, x, y) then
        return
    end
    local demo = self.demo
    if demo and demo.pointermoved then
        demo:pointermoved(id, x, y, dx, dy)
    end
    self.input:move(id, x, y, dx, dy)
end

function Game:pointerreleased(id, x, y)
    self:emit('pointerreleased', id, x, y)
    local demo = self.demo
    if demo and demo.pointerreleased then
        demo:pointerreleased(id, x, y)
    end
    self.input:release(id, x, y)
end

function Game:keypressed(key)
    if self:consume('keypressed', key) then
        return
    end
    if
        self.input.menuKey
        and key == self.input.menuKey
        and not require('source.engine.ui.widgets.textFocus').current
    then
        self.input:keypressed(key)
        return
    end
    if self.input:keypressed(key) then
        return
    end
    if key == 'escape' then
        self.pauseMenu:toggle()
    elseif self:consume('keyUnhandled', key) then
        return
    elseif key == 'space' and self.character then
        -- Jump is dispatched through the named action in Input:update.
    elseif key == 'space' then
        self.demoAnimations = not self.demoAnimations
    end
end

function Game:keyreleased(key)
    self:emit('keyreleased', key)
    self.input:keyreleased(key)
end

function Game:gamepadpressed(pad, button)
    if button == 'start' then
        self.pauseMenu:toggle()
        return
    end
    self.input:gamepadpressed(pad, button)
end

function Game:gamepadreleased(pad, button)
    self.input:gamepadreleased(pad, button)
end

function Game:pointercancelled(id)
    self.input:cancel(id)
end

function Game:textinput(text)
    if not self:consume('textinput', text) then
        self.input:textinput(text)
    end
end

function Game:pause()
    self:emit('pause')
    self.input:reset()
    self.audio:pause()
end

function Game:resume()
    self.audio:resume()
end

function Game:exit()
    self.pauseMenu:close()
    self:emit('exit')
    self.input:reset()
    self.audio:stop()
    self.manager.time:setScale(1)
end

function Game:mousebutton(button, down)
    self:emit('mousebutton', button, down)
    self.input:mapMouseButton(button, down)
end

function Game:wheelmoved(x, y)
    if self:consume('wheelmoved', x, y) then
        return
    end
    self.input:mapWheel(x, y)
    -- A scene with its own wheel handling (camera zoom) goes first.
    local demo = self.demo
    if demo and demo.wheelmoved and demo:wheelmoved(x, y) then
        return
    end
    if self.input.wheelmoved and self.input:wheelmoved(x, y) then
        return
    end
    if self._ui:wheel(katsa.mouse.getX(), katsa.mouse.getY(), y, x) then
        return
    end
    -- Orthographic free cameras have no dolly zoom (moving does not change scale), so the
    -- wheel adjusts magnification instead.
    local camera = self.camera
    if self.freeDebugCamera and camera and camera.orthographic and y ~= 0 then
        camera:zoomBy(y)
    end
end

function Game:release()
    self:emit('release')
    require('source.engine.core.cleanup').run({
        function()
            if self.systems then
                self.systems:release()
            end
        end,
        function()
            if self.lifecycle and (self.demo or self.package.instance) then
                self.lifecycle.destroy(self.demo or self.package.instance)
            elseif self.demo and self.demo.release then
                self.demo:release()
            end
        end,
        function()
            if self.physics then
                self.physics:release()
            end
        end,
        function()
            self.world:release()
        end,
        function()
            require('source.engine.scenes.rootNode').release(self.root)
        end,
        function()
            self.audio:release()
        end,
        function()
            self._ui:release()
        end,
        function()
            self.renderer:release()
        end,
        function()
            if self.resources then
                self.resources:release()
            end
        end,
        function()
            if self.package then
                self.package:release()
            end
        end,
    })
end

Modules.extend(Game)

for _, path in ipairs({ 'sceneUI', 'sceneSimulation', 'sceneRendering' }) do
    for name, method in pairs(require('game.runtime.game.' .. path)) do
        Game[name] = method
    end
end

function Game:createPhysics2D(options, ui)
    return require('source.engine.scenes.physics2D').create(self, options, ui)
end

return Game
