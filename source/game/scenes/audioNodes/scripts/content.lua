local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Mesh = require('source.engine.composition.mesh')

local Demo = {}
Demo.__index = Demo

function Demo.new(scene)
    local self = setmetatable({ scene = scene, preset = 'Dry', effects = {} }, Demo)
    scene.showStats = false
    scene.camera.position = { 0, 22, -75 }
    scene.camera.rotation = { -5, 0, 0 }
    scene.camera.drawDistance = 500
    local world = scene.world
    world.environment.fog.enabled = false
    world.environment.debug.gizmos.enabled = false
    world.environment.ambient = { 150, 160, 175 }
    Mesh.create(world, {
        name = 'AudioStage',
        kind = 'plane',
        position = { 0, 0, 20 },
        size = { 160, 0, 140 },
        surfaceAppearance = { colorMap = 'stone' },
    })
    self.emitter = Mesh.create(world, {
        name = 'Speaker',
        position = { 0, 16, 25 },
        size = { 12, 24, 12 },
        color = {
            0.15,
            0.6,
            0.9,
            1,
        },
    })
    self.group = world:create('SoundGroup', { name = 'LabMix', volume = 0.8 })
    self.groupReverb = world:create(
        'SoundReverb',
        { name = 'RoomReverb', enabled = false, decaytime = 3, volume = 0.65 },
        self.group
    )
    self.sound = world:create('Sound', {
        name = 'EffectProbe',
        resource = 'assets/audio/effects/effectProbe.wav',
        group = self.group,
        volume = 0.7,
        looped = true,
        spatial = false,
        timeScaled = false,
    }, self.emitter)
    for _, kind in ipairs({
        'SoundReverb',
        'SoundEcho',
        'SoundChorus',
        'SoundDistortion',
        'SoundPitch',
        'SoundFilter',
    }) do
        self.effects[kind] = world:create(kind, { name = kind, enabled = false }, self.sound)
    end
    local board = world:create('BillboardUI', {
        name = 'SpeakerLabel',
        position = { 0, 20, 0 },
        size = { 0, 210, 0, 55 },
        canvasSize = {
            0,
            210,
            0,
            55,
        },
    }, self.emitter)
    local label = board.ui:create('Label', {
        position = { 0, 0, 0, 0 },
        size = { 0, 210, 0, 55 },
        text = 'NODE AUDIO',
        fontSize = 24,
        backgroundColor = { 0.08, 0.15, 0.22 },
        backgroundTransparency = 1 - 1,
    }, board)
    board.ui:create('UICorner', { radius = { 0, 12 } }, label)
    board.ui:create(
        'UIStroke',
        { target = 'Border', color = { 0.2, 0.8, 1, 1 }, thickness = { 0, 2 } },
        label
    )
    board.ui:create('UIStroke', { target = 'Text', thickness = { 0, 1 } }, label)
    board.ui:create('Ramp', {
        target = 'Text',
        points = {
            { time = 0, value = { 1, 0.9, 0.4, 1 } },
            { time = 1, value = { 0.3, 1, 1, 1 } },
        },
    }, label)
    return self
end

function Demo:choose(label, kind, value)
    self.sound:stop()
    for _, effect in pairs(self.effects) do
        effect.enabled = false
        self.scene.audio:removeEffect(effect)
    end
    self.scene.audio:removeEffect(self.groupReverb)
    self.groupReverb.enabled = false
    if kind == 'Group' then
        self.groupReverb.enabled = true
    elseif kind then
        local effect = self.effects[kind]
        effect.enabled = true
        if value then
            effect.playbackSpeed = value
        end
    end
    self.preset = label
    self.sound:play()
end

function Demo:update(dt)
    if self.panel then
        self.panel.position = { 0.5, 0, 0.5, 44 }
        self.panel.size = { 0, math.min(760, self.scene.ui.width - 24), 1, -166 }
        local columns = self.scene.ui.width < 600 and 2 or 3
        local base = math.ceil(#self.presetButtons / columns) * 54
        for i, node in ipairs(self.presetButtons) do
            node.position =
                { ((i - 1) % columns) / columns, 4, 0, math.floor((i - 1) / columns) * 54 }
            node.size = { 1 / columns, -8, 0, 44 }
        end
        for i, node in ipairs(self.actionButtons) do
            node.position = { ((i - 1) % 2) / 2, 4, 0, base + math.floor((i - 1) / 2) * 50 }
            node.size = { 0.5, -8, 0, 44 }
        end
        local offset = base + 100 - 220
        for _, node in ipairs(self.body.children) do
            if
                not node._audioControl
                and not node._audioMoved
                and node.position
                and node.position[4] >= 216
                and node ~= self.status
            then
                node._audioY = node.position[4]
                node._audioMoved = true
            end
            if node._audioMoved then
                node.position[4] = node._audioY + offset
            end
        end
        self.status.position[4] = 320 + offset
        self.body.length = 420 + offset
    end
    self.scene.world:updateNodes(dt)
    if self.status then
        local messages = {}
        if self.groupReverb.enabled then
            messages[#messages + 1] = 'Group reverb: ' .. self.groupReverb.status
        end
        for _, effect in ipairs(self.sound.children) do
            if effect.enabled then
                messages[#messages + 1] = effect.className .. ': ' .. effect.status
            end
        end
        self.status.text = self.preset
            .. ' | '
            .. self.sound.status
            .. ' | '
            .. string.format('%.2f s', self.sound:tell())
            .. '\n'
            .. (#messages > 0 and table.concat(messages, '; ') or 'Dry sound; no effects enabled.')
            .. '\nPitch changes playback speed. Effects use device-supported parallel sends.'
    end
end

return Demo
