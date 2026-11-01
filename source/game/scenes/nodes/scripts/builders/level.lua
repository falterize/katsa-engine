local Mesh = require('source.engine.composition.mesh')
local UI = require('source.engine.ui')
local object = require('scene.scripts.builders.object')

local Nodes = {}

function Nodes.build(self, scene)
    self.pivot = scene.world:create('OrbitNode', { name = 'OrbitRoot', position = { 0, 45, 90 } })
    self.pivot:setProcess(true)
    self.satellite = Mesh.create(scene.world, {
        name = 'Satellite',
        position = { 55, 0, 0 },
        size = { 20, 20, 20 },
        color = { 0.3, 1, 0.6, 1 },
    }, self.pivot)
    self.socket = self.satellite:attachment({ name = 'LabelSocket', position = { 0, 20, 0 } })
    local board = UI.newBillboard(scene.world, {
        name = 'NestedAttachment',
        attachment = self.socket,
        position = { 0, 0, 0 },
        size = { 0, 320, 0, 80 },
        canvasSize = { 0, 320, 0, 80 },
        sizeMode = 'Screen',
        onTop = true,
    })
    board.ui:text({
        position = { 0, 0, 0, 0 },
        size = { 0, 320, 0, 80 },

        text = 'Node3D > Mesh3D > Attachment3D',
        fontSize = 24,
        backgroundColor = { 0.05, 0.13, 0.2 },
        backgroundTransparency = 1 - 0.95,
    }, board.ui.content)
    object.create(
        scene,
        'LayerOne',
        { -65, 15, 45 },
        { 30, 30, 30 },
        { layerGroup = 'Default', color = { 1, 0.3, 0.3, 1 } }
    )
    object.create(
        scene,
        'LayerTwo',
        { 65, 15, 45 },
        { 30, 30, 30 },
        { layerGroup = 'Player', color = { 0.2, 0.5, 1, 1 } }
    )
    scene.camera.layerGroup = 'Default'
    self.alternate = scene.world:addCamera({
        name = 'SideCamera',
        position = { -180, 80, 90 },
        rotation = { -12, 90, 0 },
        layerGroup = 'Default',
        drawDistance = 1000,
    })
    self.primary = scene.camera
end

return Nodes
