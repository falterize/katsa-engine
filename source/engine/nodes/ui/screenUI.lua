local ipairs = require('../../math.array').ipairs
local Node = require('../core.baseNode')

local C = Node.define('World2D', 'Node')
C.propertySchema = {
    layerGroup = {},
    gravity = { min = 0 },
    gravityDirection = {
        kind = 'vector',
    },
    timeScale = { min = 0, max = 100 },
    transparency = { min = 0, max = 1 },
    currentCamera = { kind = 'node', nodeClass = 'Camera2D' },
}

function C.initialize(self)
    require('source.engine.world.gravity').initialize(self, 2)
    self.layerGroup = self.layerGroup or 'Default'
    self.timeScale = self.timeScale or 1
    self.transparency = self.transparency or 0
end

function C.mount(world, properties, parent)
    -- Any node of the world may hold a World2D (a prefab copy keeps its own inside its Node3D);
    -- it belongs to the first World3D above it, which must be this world's.
    parent = parent or world._node
    local owner = parent
    while owner and owner ~= world._node do
        assert(
            not owner:isA('UINode') and not owner:isA('World2D') and not owner:isA('World3D'),
            'World2D cannot belong to a widget, another World2D or another World3D'
        )
        owner = owner.parent
    end
    assert(owner, 'World2D must be inside the World3D it belongs to')
    local ui = require('source.engine.ui')
        .new(properties.width or 640, properties.height or 360, world.resources)
        :bindWorld(world)
    ui.transparency = properties.transparency or properties.Transparency or 0
    ui.layerGroup = properties.layerGroup or properties.LayerGroup or 'Default'
    ui.name = properties.name or 'World2D'
    ui.timeScale = properties.timeScale or properties.TimeScale or 1
    if
        properties.gravity ~= nil
        or properties.Gravity ~= nil
        or properties.gravityDirection
        or properties.GravityDirection
    then
        ui.gravity = properties.gravity or properties.Gravity or ui.gravity
        ui.gravityDirection = properties.gravityDirection
            or properties.GravityDirection
            or ui.gravityDirection
        ui._gravityConfigured = true
    end
    ui.parent = parent
    ui:onDestroy(function()
        for i, item in ipairs(world.uis) do
            if item == ui then
                table.remove(world.uis, i)
                break
            end
        end
    end)
    return ui
end

return C
