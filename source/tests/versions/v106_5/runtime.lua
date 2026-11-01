local Previous = require('source.tests.versions.v106_4.runtime')
local Application = require('source.game.runtime.application')
local Game = require('source.game.runtime.game')
local Package = require('source.engine.scenes.package')
local Layout = require('source.engine.scenes.layout')
local Nodes = require('source.engine.nodes')

local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests
local fixtures = 'source/tests/fixtures/lifecycle/'

function Tests.new(manager)
    local self = Previous.new(manager)
    love.errorhandler = function(message)
        print('FAILED v106.5 ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable(self, Tests)
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v106.5', label)
end

function Tests:layout()
    local count = 0
    for _, name in ipairs(love.filesystem.getDirectoryItems('source/game/scenes')) do
        local root = 'source/game/scenes/' .. name
        self:check(love.filesystem.getInfo(root, 'directory'), 'Scene entry is a folder: ' .. name)
        local package = Package.open(root)
        self:check(
            package.settings.layoutVersion == 2 or package.settings.layoutVersion == 3,
            'Current package contract: ' .. name
        )
        Layout.validate(root, package.settings)
        local main = Layout.lifecycle(package)
        local hooks = {}
        for _, hook in ipairs(Layout.hooks) do
            hooks[hook] = true
        end
        for hook in pairs(main) do
            self:check(hooks[hook], 'main.lua exports lifecycle hooks only: ' .. name)
        end
        package:release()
        count = count + 1
    end
    self:check(
        count == #require('source.game.sceneCatalog').entries + 2,
        'All gameplay and interface scenes use folders'
    )
    local ok, message = pcall(Package.open, fixtures .. 'missingCategory.zip')
    self:check(
        not ok and tostring(message):find('category directory'),
        'Modern archives reject missing category directories'
    )
end

function Tests:systems()
    for _, suffix in ipairs({
        'basic',
        'basic.zip',
        'basic.love',
        'basic.tar',
        'basic.tar.gz',
        'basic.tgz',
        'basic.7z',
        'emptyCategories.zip',
    }) do
        local scene, message = self.manager:switch(Application.new, fixtures .. suffix)
        self:check(scene ~= nil, 'Modern package starts: ' .. suffix .. ' ' .. tostring(message))
        local state, systems = scene.demo, scene.systems
        self:check(#systems.ordered == 5, 'main.lua discovers every system module once')
        self:check(
            state.zeta.starts == 1 and state.alpha.starts == 1 and state.disabled.starts == 0,
            'Disabled systems do not run their start hook'
        )
        local uiUpdates = 0
        local updateUI = scene.ui.update
        scene.ui.update = function(ui, ...)
            uiUpdates = uiUpdates + 1
            return updateUI(ui, ...)
        end
        self.manager:update(1 / 60)
        self:check(
            table.concat(state.events, ',') == 'zeta,alpha,automatic',
            'Scene settings determine order; unlisted systems use the default'
        )
        self:check(
            state.steps == 1 and uiUpdates == 1,
            'Simulation and UI each update exactly once'
        )
        self:check(
            state.zeta.ticks == 1
                and state.zeta.three == 1
                and state.zeta.two == 1
                and state.zeta.uiDelta == 1 / 60,
            'General, 3D and 2D lifecycle callbacks receive their frame delta'
        )
        self:check(
            state.disabled.ticks == 0 and not state.disabled.three and not state.disabled.two,
            'Disabled systems skip all update phases'
        )
        systems:setEnabled('disabled', true)
        self.manager:update(1 / 60)
        self:check(
            state.disabled.starts == 1 and state.disabled.ticks == 1,
            'Scene systems can be enabled at runtime'
        )
        self:check(
            scene.world.nodeTypes.SceneProbe and not Nodes.classes.SceneProbe,
            'Archive-owned custom nodes stay local to their world'
        )
        local second = Application.new(self.manager, fixtures .. suffix)
        second:load()
        self:check(
            scene.world.nodeTypes.SceneProbe ~= second.world.nodeTypes.SceneProbe,
            'Private module instances remain isolated between package instances'
        )
        second:release()
        scene:draw()
        assert(self.manager:switch(Application.new, 'menu'))
        self:check(
            state.zeta.released and state.alpha.released and state.disabled.released,
            'Scene transitions release enabled and disabled systems'
        )
    end
end

function Tests:interfaces()
    for _, name in ipairs({ 'menu', 'nodeCatalog' }) do
        local scene, message = self.manager:switch(Application.new, name)
        self:check(scene ~= nil, 'Interface scene starts: ' .. name .. ' ' .. tostring(message))
        self.manager:update(1 / 60)
        scene:resize(960, 540)
        scene:draw()
        self:check(
            scene.state.world and scene.state.ui and scene.state.systems,
            'Interface scenes use the same lifecycle and private system ownership'
        )
    end
    local scene = assert(self.manager:switch(Application.new, 'menu'))
    local pause = assert(self.manager:push(Application.new, 'pause'))
    self.manager:update(1 / 60)
    self.manager:draw()
    self.manager:pop()
    self:check(
        self.manager.stack[1] == scene and pause.package.references == 0,
        'Pause overlay releases its package and resumes the previous scene'
    )
end

function Tests:privateNodes()
    local night = assert(self.manager:switch(Game.new, 'nightPlayer'))
    self:check(
        night.world.nodeTypes.BouncePad and night.world.nodeTypes.SceneButton,
        'Player trampoline and scene button are registered by their owning scene'
    )
    self:check(not night.world.nodeTypes.OrbitNode, 'Other scenes do not receive OrbitNode')
    local nodes = assert(self.manager:switch(Game.new, 'nodes'))
    self:check(
        nodes.world.nodeTypes.OrbitNode
            and not nodes.world.nodeTypes.BouncePad
            and not nodes.world.nodeTypes.SceneButton,
        'Node demo owns only its private custom type'
    )
    self:check(
        not Nodes.classes.BouncePad
            and not Nodes.classes.SceneButton
            and not Nodes.classes.OrbitNode,
        'Scene custom types do not pollute the engine registry'
    )
end

function Tests:portableScenes()
    for _, name in ipairs({ 'nightPlayer', 'nodes', 'animationPhysicsLab' }) do
        local scene, message = self.manager:switch(Application.new, fixtures .. name .. '.zip')
        self:check(
            scene ~= nil,
            'Real scene runs from its own archive: ' .. name .. ' ' .. tostring(message)
        )
        self:check(
            scene.package.root:sub(1, 15) == '_scenePackages/',
            'Private code resolves from the mounted scene root'
        )
        self.manager:update(1 / 60)
        scene:draw()
    end
    local broken = Application.new(self.manager, fixtures .. 'failedStart.zip')
    local ok, message = pcall(broken.load, broken)
    local root = broken.package.root
    self:check(
        not ok and tostring(message):find('Expected startup failure'),
        'Initialization failure is reported at the system start hook'
    )
    local state = broken.package.instance
    self:check(pcall(broken.release, broken), 'Partially initialized scene can be released')
    self:check(
        state.zeta.released and state.alpha.released and state.failedStart.released,
        'Failed startup releases all constructed systems'
    )
    self:check(
        not love.filesystem.getInfo(root .. '/main.lua'),
        'Failed startup releases archive resource leases'
    )
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:layout()
    self:scenePackages()
    self:allScenes()
    self:systems()
    self:interfaces()
    self:privateNodes()
    self:portableScenes()
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' v106.5 checks')
    love.event.quit()
end

return Tests
