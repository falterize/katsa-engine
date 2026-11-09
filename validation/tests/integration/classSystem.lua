local Nodes = require('source.engine.nodes')
local UI = require('source.engine.ui')
local World3D = require('source.engine.world.world')
local Resources = require('source.engine.core.resources')
return function(test)
    local Spinner = Nodes.define('TestSpinner', 'Mesh3D')

    function Spinner.initialize(self)
        self.angularSpeed = self.angularSpeed or 30
    end

    function Spinner:advance(dt)
        self.rotation[2] = self.rotation[2] + self.angularSpeed * dt
    end
    Spinner.update = Spinner.advance
    local resources = Resources.new(require('source.game.data.manifest'))
    local world = World3D.new(resources, require('source.game.data.settings').create())
    local first = world:create('TestSpinner', { name = 'First', angularSpeed = 90 })
    local second = world:create('TestSpinner', { name = 'Second' })
    first:advance(0.5)
    test:check(
        first.rotation[2] == 45 and second.rotation[2] == 0,
        'Custom node class owns methods and independent properties'
    )
    test:check(
        first:isA('TestSpinner')
            and first:isA('Mesh3D')
            and first:isA('Node3D')
            and first:isA('Node'),
        'isA follows the declared inheritance chain'
    )
    test:check(
        first.advance == second.advance and first._class == Spinner,
        'Node instances share their real class methods'
    )
    first:setProcess(true)
    world:updateNodes(0.5)
    world:updateNodes(0)
    test:check(
        first.rotation[2] == 90,
        'NodeTree processes registered class scripts with scaled time'
    )
    first:setProcess(false)
    world:updateNodes(1)
    test:check(first.rotation[2] == 90, 'Node processing can be disabled explicitly')
    local ui = UI.new(100, 100, resources)
    local Label = Nodes.define('TestStatusLabel', 'Label')

    function Label:drawSelf(owner)
        self.drawCount = (self.drawCount or 0) + 1
        Label.base.drawSelf(self, owner)
    end
    local node = ui:create('TestStatusLabel', { width = 100, height = 60, text = 'OK' }, ui.content)
    local canvas = katsa.graphics.newCanvas(100, 100)
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(canvas)
    ui:draw()
    katsa.graphics.pop()
    test:check(
        node:isA('UINode') and node.drawCount == 1,
        'Custom UI class uses polymorphic drawing without kind aliases'
    )
    local called = 0
    local connection = node:connect('press', function()
        called = called + 1
    end)
    ui:pointer(node, 'press', 10, 10, 'first')
    connection:disconnect()
    ui:pointer(node, 'press', 10, 10, 'second')
    test:check(called == 1, 'Node event connections support explicit disconnection')
    local ownedConnection = first:connect('destroying', function()
        first:destroy()
    end)
    first:destroy()
    test:check(
        first.destroyed and not ownedConnection.connected and not world.byName.First,
        'Destroy is reentrant-safe and cleans event subscriptions and world ownership'
    )
    local previous = second.parent
    local valid = pcall(second.setParent, second, {})
    test:check(
        not valid and second.parent == previous,
        'Invalid reparenting preserves the existing hierarchy'
    )
    ui:release()
    world:release()
    canvas:release()
    resources:release()
end
