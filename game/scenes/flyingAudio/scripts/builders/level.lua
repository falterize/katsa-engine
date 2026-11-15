local UI = require('source.engine.ui')
local object = require('./object')

local FlyingAudio = {}

function FlyingAudio.build(self, scene)
    self.flying = object.create(
        scene,
        'FlyingSpeaker',
        { 0, 65, 80 },
        { 24, 24, 24 },
        { color = { 0.2, 0.85, 1, 1 } },
        { type = 'Kinematic', collider = { shape = 'Sphere', radius = 12 } }
    )
    self.emitter = self.flying:attachment({ name = 'StereoEmitter', position = { 0, 8, 0 } })
    self.voice = scene.audio:play('assets/audio/music/demoMusic.wav', {
        object = self.emitter,
        loop = true,
        group = 'effects',
        volume = 0.8,
        minDistance = 35,
        maxDistance = 260,
        stereoWidth = 14,
    })
    self.board = UI.newBillboard(scene.world, {
        name = 'EmitterInfo',
        attachment = self.emitter,
        position = { 0, 20, 0 },
        size = { 0, 330, 0, 90 },
        canvasSize = { 0, 330, 0, 90 },
        sizeMode = 'Screen',
        onTop = true,
    })
    self.board.ui:text({
        position = { 0, 0, 0, 0 },
        size = { 0, 330, 0, 90 },

        text = 'MOVING STEREO EMITTER\nFull volume 35 / silent 260',
        fontSize = 23,
        backgroundColor = { 0.05, 0.15, 0.22 },
        backgroundTransparency = 1 - 0.9,
    }, self.board.ui.content)
end

return FlyingAudio
