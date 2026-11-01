local Game = require('source.game.runtime.game')
local Application = require('source.game.runtime.application')
local Package = require('source.engine.scenes.package')
local Loader = require('source.engine.scenes.loader')
local Resources = require('source.engine.core.resources')
local Systems = require('source.engine.scenes.systems')
local Catalog = require('source.game.sceneCatalog')
local Models = require('source.engine.import.models')

local Tests = {}
Tests.__index = Tests
local fixture = 'validation/tests/fixtures/scenes/'

function Tests.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED v106.4 ' .. tostring(message))
        os.exit(1)
    end
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    return setmetatable({ manager = manager, count = 0 }, Tests)
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v106.4', label)
end

function Tests:package(source)
    local package = Package.open(source)
    local root = package.root
    self:check(package.settings.id == 'packageFixture', 'Package metadata: ' .. root)
    local resources =
        self.manager.resources:scope(Loader.manifest(nil, package.settings.assets), package.paths)
    local second = self.manager.resources:scope(nil, package.paths)
    local image = resources:image('scene://textures/checker.png')
    self:check(
        not resources:isMissingImage('scene://textures/checker.png'),
        'Local image resolves inside mounted package'
    )
    self:check(resources:image('thumbnail') == image, 'Manifest alias shares the same image')
    self:check(
        second:image('shared://textures/internal/white.png')
            == resources:image('assets/textures/internal/white.png'),
        'Shared and ordinary paths share one native asset'
    )
    self:check(
        resources:canonical('shared://textures/../textures/internal/white.png')
            == 'assets/textures/internal/white.png',
        'URI normalization remains inside its namespace'
    )
    self:check(
        not pcall(resources.canonical, resources, 'scene://../escape.png'),
        'Local URI cannot escape its root'
    )
    self:check(
        not pcall(resources.canonical, resources, 'unknown://image.png'),
        'Unknown URI namespaces are rejected'
    )
    local model = Models.load('scene://models/skinRibbon.gltf', resources)
    self:check(
        Models.load('ribbon', resources).parts[1].geometry == model.parts[1].geometry,
        'Model alias shares immutable geometry'
    )
    self:check(
        #model.parts > 0 and #model.animations > 0,
        'GLTF loads relative external buffers inside package'
    )
    local obj = Models.load('scene://models/pyramid.obj', resources)
    self:check(
        #obj.parts > 0 and obj.parts[1].material.image ~= nil,
        'OBJ loads relative MTL and texture dependencies'
    )
    local audio = self.manager.audio:scope(resources:scope())
    local voice = audio:play('click', { volume = 0 })
    self:check(voice ~= nil, 'Local URI resolves for audio playback')
    audio:release()
    package:release()
    self:check(
        katsa.filesystem.getInfo(root .. '/settings.lua') ~= nil,
        'Asset scopes retain the mounted package'
    )
    resources:release()
    second:release()
    self:check(
        not package.archive or not katsa.filesystem.getInfo(root .. '/settings.lua'),
        'Last resource scope unmounts package'
    )
end

function Tests:scenePackages()
    local firstData = katsa.filesystem.newFileData(
        assert(katsa.filesystem.read(fixture .. 'basic.zip')),
        'scene.zip'
    )
    local secondData = katsa.filesystem.newFileData(
        assert(katsa.filesystem.read(fixture .. 'wrapped.zip')),
        'scene.zip'
    )
    local first, second = Package.open(firstData), Package.open(secondData)
    self:check(
        first.root ~= second.root
            and katsa.filesystem.getInfo(first.root .. '/settings.lua')
            and katsa.filesystem.getInfo(second.root .. '/settings.lua'),
        'Different archives with identical filenames mount independently'
    )
    first:release()
    self:check(
        katsa.filesystem.getInfo(second.root .. '/settings.lua'),
        'Unmounting one archive preserves another with the same filename'
    )
    second:release()
    for _, extension in ipairs({ 'zip', 'love', 'tar', 'tar.gz', 'tgz', '7z' }) do
        self:package(fixture .. 'basic.' .. extension)
    end
    self:package(fixture .. 'basic')
    self:package(fixture .. 'wrapped.zip')
    self:check(
        not pcall(Package.open, fixture .. 'invalid.zip'),
        'Malformed package is rejected without a live mount'
    )
    self:check(
        not pcall(Package.open, fixture .. 'ambiguous.zip'),
        'Ambiguous archive root is rejected'
    )
    self:check(
        not pcall(Package.open, fixture .. 'corrupt.tar'),
        'Corrupt TAR checksum is rejected'
    )
    local scene = assert(self.manager:switch(Game.new, fixture .. 'basic.zip'))
    self:check(
        scene.zone == 'packageFixture' and scene.physics.backendName == 'oimo',
        'Archive scene uses its own stable ID and backend'
    )
    self.manager:update(0.01)
    self:check(scene.demo.counter.ticks > 0, 'main.lua starts the registered system')
    local previous = scene.demo.counter.ticks
    scene.systems:setEnabled('counter', false)
    self.manager:update(0.01)
    self:check(scene.demo.counter.ticks == previous, 'Disabled system receives no updates')
    scene.systems:setEnabled('counter', true)
    self.manager:update(0.01)
    self:check(scene.demo.counter.ticks > previous, 'System can be enabled again')
    scene:draw()
    local other = Game.new(self.manager, fixture .. 'basic.zip')
    other:load()
    self:check(
        other.world.nodeTypes.Counter ~= scene.world.nodeTypes.Counter,
        'Identical custom node names are isolated per world'
    )
    other:release()
    self:check(
        not scene.demo.system.released,
        'Releasing another instance preserves the active system'
    )
    local system, root = scene.demo.system, scene.package.root
    assert(self.manager:switch(Game.new, 'physics'))
    self:check(
        system.released and not katsa.filesystem.getInfo(root .. '/settings.lua'),
        'Scene switch releases systems and archive scopes'
    )
    local updates, starts = 0, 0
    local systems = Systems.new({})
    systems:add('disabled', {
        start = function()
            starts = starts + 1
        end,
        update = function()
            updates = updates + 1
        end,
    }, false)
    systems:update(0.1)
    self:check(starts == 0 and updates == 0, 'Initially disabled system does not start')
    systems:setEnabled('disabled', true)
    systems:update(0.1)
    systems:setEnabled('disabled', false)
    systems:setEnabled('disabled', true)
    self:check(starts == 1 and updates == 1, 'System initialization runs only once')
    systems:release()
    local order = {}
    local failing = Systems.new({})
    failing:add('first', {
        release = function()
            order[#order + 1] = 'first'
        end,
    })
    failing:add('last', {
        release = function()
            order[#order + 1] = 'last'
            error('Expected release fixture')
        end,
    })
    self:check(
        not pcall(failing.release, failing) and table.concat(order, ',') == 'last,first',
        'System shutdown finishes in reverse order even when a hook fails'
    )
    self:check(
        pcall(failing.release, failing),
        'System release remains idempotent after a failed hook'
    )
end

function Tests:allScenes()
    for _, backend in ipairs({ 'jolt', 'oimo' }) do
        for _, entry in ipairs(Catalog.entries) do
            if not entry.interface then
                local scene, message
                if entry.standalone then
                    scene, message =
                        self.manager:switch(Application.new, entry.id, { physicsBackend = backend })
                else
                    scene, message =
                        self.manager:switch(Game.new, entry.id, { physicsBackend = backend })
                end
                self:check(scene ~= nil, entry.id .. ': ' .. tostring(message or backend))
                self:check(
                    scene.settings.id == entry.id and scene.package.root == entry.path,
                    'Catalog selects the correct folder'
                )
                self.manager:update(1 / 60)
                scene:draw()
                self:check(
                    not scene.physics or scene.physics.backendName == backend,
                    'Requested solver is preserved'
                )
                if entry.id == 'combined' then
                    self:check(
                        scene.stressMotion ~= nil,
                        'Stress controls retain their public scene handle'
                    )
                    local motion = scene.stressMotion
                    motion.cubeButton.onPress()
                    motion.lightButton.onPress()
                    local cubeY = motion.cube.position.y
                    self.manager:update(1 / 60)
                    self:check(
                        motion.cube.position.y ~= cubeY,
                        'Named stress system updates enabled motion'
                    )
                    scene.ui:fit(320, 240)
                    motion:resize()
                    self:check(
                        motion.panel.size[2] <= scene.ui.width - 20,
                        'Stress controls retain compact-window resizing'
                    )
                end
            end
        end
    end
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:scenePackages()
    self:allScenes()
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' v106.4 checks')
    katsa.event.quit()
end

return Tests
