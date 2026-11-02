local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')

local Scene = {}
Scene.__index = Scene

function Scene.new(scene)
    local data = require('./data.layout')
    for _, entry in ipairs(data.objects) do
        local a = entry.args
        Mesh.create(scene.world, {
            name = tostring(a[1]),
            kind = entry.kind,
            position = { unpack(a[2]) },
            size = { unpack(a[3]) },
            surfaceAppearance = { colorMap = a[4] },
        })
    end
    scene.world.byName.Sphinx.size[2] = 150
    for _, a in ipairs(data.lights) do
        scene.world:addLight({
            name = a[1],
            position = { unpack(a[2]) },
            type = a[3],
            rotation = { unpack(a[4]) },
            color = { unpack(a[5]) },
            brightness = a[6],
            range = a[7],
            radius = a[8],
            enabled = a[9],
            rainbow = a[10],
        })
    end
    scene.rainbowMotion =
        { enabled = true, center = { 0, 15, -100 }, amplitude = 25, arc = 55, period = 5, hz = 15 }
    scene.boards = require('./ui.world.billboards').build(scene)
    return setmetatable({ scene = scene }, Scene)
end

function Scene:update(dt)
    self.scene.world:updateNodes(dt)
end

return Scene
