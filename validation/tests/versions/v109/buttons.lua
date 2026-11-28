-- Button2D makes any UI node clickable; Button3D `includeDescendants` limits a model's hit area.
local Node = require('source.engine.nodes')
local Resources = require('source.engine.core.resources')
local UI = require('source.engine.ui')

local Module = {}

function Module.run(self)
    local ui = UI.new(100, 100, Resources.new(require('validation.tests.fixtures.manifest')))
    ui.parent = Node.new('World3D', {})
    local label = ui:create('Label', { x = 10, y = 10, width = 40, height = 40, text = 'Go' }, ui.content)
    local overflow = ui:create('Frame', { x = 50, y = 0, width = 20, height = 20 }, label)
    ui:layout()
    self:check(ui:hit(70, 15) == nil, 'a plain Label is not a pointer target')
    local button = ui:create('Button2D', { includeDescendants = false }, label)
    ui:layout()
    self:check(ui:hit(20, 20) == label, 'a Button2D makes its parent a pointer target')
    self:check(ui:hit(65, 20) == nil, 'with includeDescendants off an overflowing child is not part of the button')
    button.includeDescendants = true
    ui:invalidate()
    ui:layout()
    self:check(ui:hit(65, 20) == overflow, 'includeDescendants (the default) adds descendants overflowing the target')
    local seen = 0
    button:connect('click', function(id, target)
        seen = seen + (target == label and id == 'code' and 1 or 0)
    end)
    label:click()
    self:check(seen == 1, 'Button2D emits click with (pointer id, target) like Button3D')
    button.enabled = false
    ui:invalidate()
    ui:layout()
    self:check(ui:hit(20, 20) == nil, 'a disabled Button2D stops making the parent clickable')
    -- A Node2D target: its UI children are the hit area (a physics body's picture works alike).
    local group = ui:create('Node2D', { position = { 60, 60 }, size = { 30, 30 } })
    local picture = ui:create('Frame', { width = 30, height = 30 }, group)
    ui:layout()
    self:check(ui:hit(75, 25) == nil, 'a Node2D without a Button2D is not a pointer target')
    local groupButton = ui:create('Button2D', {}, group)
    ui:layout()
    local seenGroup = 0
    groupButton:connect('click', function()
        seenGroup = seenGroup + 1
    end)
    local found = ui:hit(75, 25)
    self:check(found == picture, 'a Button2D on a Node2D makes its UI children clickable')
    ui:pointer(found, 'press', 75, 25, 'mouse')
    ui:pointer(found, 'release', 75, 25, 'mouse')
    self:check(seenGroup == 1, 'the Node2D button receives the click of a descendant')
    overflow:destroy()
    ui:release()
end

-- A physical Body2D is a Node2D: a Button2D on it makes its picture clickable while it moves.
function Module.physics(self)
    local World = require('source.engine.world.world')
    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    local ui = world:create('World2D', { width = 200, height = 200 })
    ui:createPhysics({ gravity = { 0, 0 } })
    local body = ui:create('Body2D', {
        position = { 100, 100 },
        size = { 40, 40 },
        bodyType = 'Dynamic',
        collider = { shape = 'Box', size = { 40, 40 } },
    })
    local picture = ui:create('Frame', { width = 40, height = 40 }, body)
    local clicks = 0
    ui:create('Button2D', {}, body):connect('click', function()
        clicks = clicks + 1
    end)
    ui:layout()
    local x, y = 100, 100
    local hit = ui:hit(x, ui.height - y)
    self:check(hit ~= nil, 'a Button2D on a Body2D makes its picture a pointer target')
    if hit then
        ui:pointer(hit, 'press', x, ui.height - y, 'mouse')
        ui:pointer(hit, 'release', x, ui.height - y, 'mouse')
    end
    self:check(clicks == 1, 'the Body2D button receives the click')
    world:release()
    resources:release()
end

return Module
