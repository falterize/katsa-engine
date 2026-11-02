local ipairs = require('../../math.array').ipairs
local Node = require('../core.baseNode')

local C = Node.define('World2D', 'Node')
C.propertySchema = {
    layerGroup = {},
    gravity = { min = 0, hint = 'Acceleration magnitude in world units per second squared.' },
    gravityDirection = {
        kind = 'vector',
        hint = 'World-space direction; normalized by the solver. Zero disables gravity.',
    },
    timeScale = { min = 0, max = 100 },
    transparency = { min = 0, max = 1 },
    currentCamera = { kind = 'node', nodeClass = 'Camera2D' },
}

function C.initialize(self)
    require('../../world.gravity').initialize(self, 2)
    self.layerGroup = self.layerGroup or 'Default'
    self.timeScale = self.timeScale or 1
    self.transparency = self.transparency or 0
end

function C.mount(world, properties, parent)
    assert(parent == world.root, 'World2D belongs directly to its World3D')
    local ui = require('../../ui')
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
