require('validation.tests.integration.luaCompatibility')
local Node = require('source.engine.nodes')
local Math = require('source.engine.math.math3d')
local Faces = require('source.engine.world.surfaces.faces')
local Receivers = require('source.engine.graphics.shadows.shadowReceivers')

local count = 0

local function check(ok, msg)
    assert(ok, msg)
    count = count + 1
    print('PASS ' .. msg)
end
local root = Node.new('World3D', {})
local mesh = Node.new('Mesh3D', {
    size = { 20, 30, 40 },
    matrix = Math.identity(),
    geometry = {
        vertices = { { -0.5, -0.5, -0.5 }, { 0.5, 0.5, 0.5 } },
    },
}, root)
local panel = Node.new('SurfaceUI', {
    canvasSize = { 0, 200, 0, 300 },
    resolvedCanvasSize = { 200, 300 },
    size = { 1, 0, 1, 0 },
    position = { 0.5, 0, 0.5, 0 },
    spatialPosition = { 0, 0, 0 },
    face = 'Front',
    transparency = 0,
    maxDistance = 500,
    matrix = Math.identity(),
    normal = {},
    surfaceOffset = 0.1,
}, mesh)
local camera = {
    position = { 0, 0, -100 },
    worldPosition = { 0, 0, -100 },
    right = { 1, 0, 0 },
    up = { 0, 1, 0 },
    forward = { 0, 0, 1 },
    width = 800,
    height = 600,
    focal = 400,
    project = function(_, p)
        return 400 + p[1] * 400 / (p[3] + 100), 300 - p[2] * 400 / (p[3] + 100), p[3] + 100
    end,
}
Faces.update(panel, camera)
check(
    panel.drawable
        and panel.worldPosition[3] == -20.1
        and panel.worldWidth == 20
        and panel.worldHeight == 30,
    'Front face uses parent geometry dimensions and outward offset'
)
local x, y, t = Faces.point(panel, camera, 400, 300)
check(
    math.abs(x - 100) < 1e-8 and math.abs(y - 150) < 1e-8 and t > 0,
    'Surface ray maps front-center to canvas center'
)
local expected = {
    Back = { 3, 20.1 },
    Left = { 1, -10.1 },
    Right = { 1, 10.1 },
    Top = { 2, 15.1 },
    Bottom = {
        2,
        -15.1,
    },
}
for face, values in pairs(expected) do
    panel.face = face
    Faces.update(panel, camera)
    check(
        math.abs(panel.worldPosition[values[1]] - values[2]) < 1e-8,
        face .. ' uses the correct local parent face'
    )
end
panel.face = 'Front'
mesh.position[1] = 50
mesh.rotation[2] = 90
Faces.update(panel, camera)
check(
    math.abs(panel.worldPosition[1] - 70.1) < 1e-7,
    'Parent rotation and translation move the local face'
)
mesh.scale = { 2, 2, 2 }
Faces.update(panel, camera)
check(
    math.abs(panel.worldWidth - 40) < 1e-7 and math.abs(panel.worldHeight - 60) < 1e-7,
    'Parent scale affects panel size independently of geometry dimensions'
)
check(
    not pcall(panel.setParent, panel, Node.new('Folder', {}, root)),
    'Surface rejects nonspatial parenting atomically'
)
local socket = Node.new('Attachment3D', {}, mesh)
panel.size = { 0, 12, 0, 8 }
panel.parent = socket
Faces.update(panel, camera)
check(
    math.abs(panel.worldWidth - 12) < 1e-7,
    'Attachment3D honors its default excluded parent scale'
)
local recv = {
    geometry = { vertices = { { -0.5, -0.5, -0.5 }, { 0.5, 0.5, 0.5 } } },
    matrix = Math.compose({ 0, 0, 100 }, { 0, 0, 0 }, { 10, 10, 10 }),
    transparency = 0,
}
local list = Receivers.collect({ recv }, { position = { 0, 0, 0 } }, 40)
check(#list == 0, 'Shadow receiver collection excludes geometry outside distance')
recv.matrix = Math.compose({ 0, 0, 20 }, { 0, 0, 0 }, { 10, 10, 10 })
list = Receivers.collect({ recv }, { position = { 0, 0, 0 } }, 40, list)
check(#list == 1, 'Receiver movement into distance updates cached world bounds')
local floor = {
    geometry = { vertices = { { -0.5, 0, -0.5 }, { 0.5, 0, 0.5 } } },
    matrix = Math.compose({ 0, -60, 0 }, { 0, 0, 0 }, { 1000, 1, 1000 }),
    transparency = 0,
}
list = Receivers.collect({ floor }, { position = { 0, 0, 0 } }, 40, list)
check(#list == 0, 'Large floor bounds do not falsely overlap a smaller distance sphere above it')
recv.receiveShadow = false
list = Receivers.collect({ recv }, { position = { 0, 0, 0 } }, 40, list)
check(#list == 0, 'Nonreceiving geometry does not request a map')
recv.receiveShadow = true
recv.matrix = Math.compose({ 0, 0, 100 }, { 0, 0, 0 }, { 10, 10, 10 })
recv.material = {}
list = Receivers.collect({ recv }, { position = { 0, 0, 0 } }, 40, list)
check(
    #list == 1 and list[1].conservative,
    'Unknown vertex materials retain conservative receiver coverage'
)
root:destroy()
check(panel.destroyed and socket.destroyed, 'Surface hierarchy destruction cleans descendants')
print('PASSED ' .. count .. ' surface pose/ray/receiver assertions')
