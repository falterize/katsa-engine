local Previous = require('source.tests.versions.v106_5.runtime')
local Application = require('source.game.runtime.application')

local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

local function hasOnlyEntries(path, allowed)
    for _, name in ipairs(love.filesystem.getDirectoryItems(path)) do
        if love.filesystem.getInfo(path .. '/' .. name, 'file') and not allowed[name] then
            return false
        end
    end
    return true
end

local function markerFree(path)
    for _, name in ipairs(love.filesystem.getDirectoryItems(path)) do
        if name == '.keep' then
            return false
        end
        local child = path .. '/' .. name
        if love.filesystem.getInfo(child, 'directory') and not markerFree(child) then
            return false
        end
    end
    return true
end

function Tests.new(manager)
    local self = Previous.new(manager)
    love.errorhandler = function(message)
        print('FAILED v106.6 ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable(self, Tests)
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v106.6', label)
end

function Tests:layout()
    Previous.layout(self)
    for _, name in ipairs(love.filesystem.getDirectoryItems('source/game/scenes')) do
        local root = 'source/game/scenes/' .. name
        self:check(
            not love.filesystem.getInfo(root .. '/ui'),
            'UI code belongs under scripts: ' .. name
        )
        self:check(
            hasOnlyEntries(root .. '/scripts', { ['content.lua'] = true }),
            'Script helpers are categorized: ' .. name
        )
        self:check(
            hasOnlyEntries(root .. '/scripts/ui', {
                ['interface.lua'] = true,
                ['controller.lua'] = true,
            }),
            'UI helpers are categorized: ' .. name
        )
    end
    self:check(
        markerFree('source/game/scenes'),
        'All scene categories survive without marker files'
    )
end

function Tests:systems()
    Previous.systems(self)
    local scene, message =
        self.manager:switch(Application.new, 'source/tests/fixtures/lifecycle/rootDirectory.tar')
    self:check(scene ~= nil, 'TAR root directory and empty categories load: ' .. tostring(message))
    self.manager:update(1 / 60)
    self:check(
        scene.demo.steps == 1,
        'TAR scene lifecycle remains active without directory markers'
    )
    scene:draw()
    local legacy = assert(
        self.manager:switch(Application.new, 'source/tests/fixtures/lifecycle/legacyLayout.zip')
    )
    self.manager:update(1 / 60)
    self:check(
        legacy.settings.layoutVersion == 2 and legacy.demo.steps == 1,
        'Earlier archives with a root UI directory remain loadable'
    )
end

function Tests:nodeAuthoring()
    local Node = require('source.engine.nodes')
    local Package = require('source.engine.scenes.package')
    local package = Package.open('source/tests/fixtures/lifecycle/basic')
    local resources = self.manager.resources:scope(nil, package.paths)
    local world = require('source.engine.world.world').new(resources)
    package:registerNodes(world, { 'spinner' })
    local before = #world.objects
    local spinner = world:create('Spinner', {
        name = 'GuideSpinner',
        size = { 20, 20, 20 },
        position = { 4, 0, 0 },
    }, world.root)
    self:check(
        spinner:isA('Mesh3D') and spinner.spinSpeed == 45 and #world.objects == before + 1,
        'Guide node inherits mounting and property defaults'
    )
    world:updateNodes(0.5)
    self:check(
        spinner:hasTag('Animated') and spinner.rotation[2] == 22.5,
        'Guide node starts and updates automatically through World:create'
    )
    spinner:setProcess(false)
    world:updateNodes(0.5)
    self:check(spinner.rotation[2] == 22.5, 'setProcess(false) suspends custom processing')
    spinner:setProcess(true)
    world:updateNodes(0.5)
    self:check(spinner.rotation[2] == 45, 'Custom node processing can resume')
    local raw = { name = 'AdoptedGuideNode', position = { 1, 2, 3 } }
    self:check(
        Node.adopt(raw, 'Node3D') == raw and raw:isA('Node3D'),
        'adopt initializes the existing table rather than allocating a new instance'
    )
    self:check(
        Node.adopt(raw, 'Folder') == raw and raw:isA('Node3D'),
        'adopt is idempotent and does not reclassify an existing node'
    )
    raw:setParent(world.root)
    local child = Node.create('Folder', { name = 'GuideChild' }, raw, world)
    child:addTag('Guide')
    self:check(
        raw:find('GuideChild') == child and world.root:findByTag('Guide', true) == child,
        'Hierarchy and tag queries find the authored node'
    )
    local snapshot = raw:getChildren()
    snapshot[1] = nil
    self:check(
        #raw.children == 1 and #raw:getDescendants() == 1,
        'Hierarchy query results do not expose the live child array'
    )
    local received, releases = 0, 0
    local connection = spinner:connect('guidePing', function(value)
        received = value
    end)
    child:trackConnection(connection)
    child:own({
        release = function()
            releases = releases + 1
        end,
    })
    spinner:emit('guidePing', 7)
    self:check(received == 7, 'Custom signal arguments reach connected callbacks')
    raw:destroy()
    raw:destroy()
    spinner:emit('guidePing', 9)
    self:check(
        child.destroyed and not connection.connected and releases == 1 and received == 7,
        'Destroy recursively releases owned resources and tracked external connections once'
    )
    spinner:destroy()
    self:check(spinner.wasReleased, 'Custom initialization cleanup runs when its node is destroyed')
    world:release()
    resources:release()
    package:release()
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
    self:nodeAuthoring()
    require('source.tests.versions.v106_6.stareShooter').run(self)
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' v106.6 checks')
    love.event.quit()
end

return Tests
