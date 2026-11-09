-- Node:clone(properties, parent): deep copies with overrides, descendants and isolation.
local World = require('source.engine.world.world')

local Module = {}

function Module.run(self)
    local world = World.new(self.manager.resources:scope())
    local car = world:create('Mesh3D', {
        name = 'Car',
        position = { 1, 2, 3 },
        size = { 2, 1, 4 },
        color = { 200, 40, 40 },
    })
    local wheel = world:create('Mesh3D', { name = 'Wheel', position = { 1, 0, 0 } }, car)
    world:create('PointLight3D', { name = 'Lamp', range = 12 }, car)

    local copy = car:clone({ Name = 'ClonedTest' })
    self:check(
        copy ~= car and copy.name == 'ClonedTest',
        'clone returns a new node with Name override'
    )
    self:check(
        copy.className == 'Mesh3D' and copy.parent == car.parent,
        'clone keeps class and parent'
    )
    self:check(
        copy.position[1] == 1 and copy.position[2] == 2 and copy.position[3] == 3,
        'clone copies vector properties'
    )
    self:check(copy.size[3] == 4 and copy.color[1] == 200, 'clone copies size and color')
    self:check(
        #copy.children == 2 and copy:find('Wheel_2') and copy:find('Wheel_2') ~= wheel,
        'clone copies descendants as new nodes with unique names'
    )
    self:check(copy:find('Lamp').range == 12, 'clone copies descendant properties')

    copy.position = { 9, 9, 9 }
    self:check(car.position[1] == 1, 'clone does not share mutable vectors with the source')

    local other = world:create('Mesh3D', { name = 'Holder' })
    local moved = car:clone({ position = { 5, 0, 0 } }, other)
    self:check(
        moved.parent == other and moved.position[1] == 5 and car.position[1] == 1,
        'clone accepts a parent and property overrides'
    )

    local ui = world:create('World2D', { width = 800, height = 600 })
    local group = ui:create('CanvasGroup', { name = 'Group', size = { 1, 0, 1, 0 } }, ui.content)
    local panel = world:create('Frame', { name = 'Panel', size = { 0, 100, 0, 50 } }, group)
    world:create('Label', { name = 'Title', text = 'Hello' }, panel)
    local panelCopy = panel:clone({ Name = 'PanelCopy' })
    self:check(
        panelCopy.parent == group
            and panelCopy:find('Title').text == 'Hello'
            and panelCopy.name == 'PanelCopy',
        'clone copies UI nodes with their children'
    )

    copy:destroy()
    self:check(
        car:find('Wheel') == wheel and not wheel.destroyed,
        'destroying a clone leaves the source intact'
    )
end

return Module
