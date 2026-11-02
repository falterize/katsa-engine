local Mesh = require('source.engine.composition.mesh')
local Models = require('source.engine.import.models')

-- XBot in its rest pose with four IK modifiers driven by two orbiting spheres:
--   right arm  TwoBone  -> red sphere (elbow hint points outward)
--   head/neck  LookAt   -> red sphere (weighted over spine, neck and head)
--   left arm   Fabrik   -> blue sphere
--   left leg   Ccd      -> floor marker (limited joints)
local Lab = {}
Lab.__index = Lab

local PREFIX = 'mixamorig:'

function Lab.new(scene)
    local IK = require('source.engine.plugins').require('ik')
    local self = setmetatable({ scene = scene, time = 0 }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.sky.enabled = false
    world.environment.ambient = { 160, 175, 190 }
    require('source.engine.plugins').require('ik')
    scene.camera.position = { 0, 70, -110 }
    scene.camera.rotation = { -8, 0, 0 }
    Mesh.create(world, {
        name = 'IKFloor',
        position = { 0, -3, 40 },
        size = { 300, 6, 200 },
        surfaceAppearance = { colorMap = 'stone' },
    })
    world:create('DirectionalLight3D', {
        name = 'Sun',
        rotation = { 63.4, 53.1, 0 },
        color = { 255, 238, 210 },
        brightness = 1,
    })
    world.environment.shadows.enabled = true
    self.model = Models.load('assets/models/characters/xbot.glb', scene.resources)
    Models.instantiate(
        world,
        self.model,
        { name = 'IKBot', position = { 0, 0, 40 }, rotation = { 0, 180, 0 }, scale = { 0.55, 0.55, 0.55 } }
    )
    local animator = self.model.animator
    animator.debugEnabled = true
    self.red = Mesh.create(world, {
        name = 'RedTarget',
        kind = 'sphere',
        size = { 6, 6, 6 },
        color = { 1, 0.2, 0.2, 1 },
    })
    self.blue = Mesh.create(world, {
        name = 'BlueTarget',
        kind = 'sphere',
        size = { 6, 6, 6 },
        color = { 0.3, 0.5, 1, 1 },
    })
    self.floorMark = Mesh.create(world, {
        name = 'FloorTarget',
        kind = 'sphere',
        size = { 5, 5, 5 },
        color = { 0.2, 1, 0.4, 1 },
    })
    self.hint = Mesh.create(world, {
        name = 'ElbowHint',
        size = { 3, 3, 3 },
        color = { 0.8, 0.8, 0.2, 1 },
        position = { -45, 75, 20 },
    })
    local function bone(name)
        return PREFIX .. name
    end
    self.modifiers = {
        arm = IK.TwoBone.new({
            root = bone('RightArm'),
            mid = bone('RightForeArm'),
            tip = bone('RightHand'),
            target = self.red,
            pole = self.hint,
            softness = 2,
            debug = true,
        }),
        look = IK.LookAt.new({
            bones = { bone('Spine2'), bone('Neck'), bone('Head') },
            weights = { 0.2, 0.3, 0.5 },
            forward = { 0, 0, 1 },
            target = self.red,
            maxAngle = 70,
            speed = 8,
            debug = true,
        }),
        fabrik = IK.Fabrik.new({
            bones = { bone('LeftArm'), bone('LeftForeArm'), bone('LeftHand') },
            target = self.blue,
            debug = true,
        }),
        leg = IK.Ccd.new({
            bones = { bone('LeftUpLeg'), bone('LeftLeg'), bone('LeftFoot') },
            target = self.floorMark,
            iterations = 12,
            limits = { [bone('LeftUpLeg')] = 50, [bone('LeftLeg')] = 70 },
            debug = true,
        }),
    }
    for _, modifier in pairs(self.modifiers) do
        modifier:attach(animator)
    end
    self.influence = 1
    return self
end

function Lab:setInfluence(value)
    self.influence = value
    for _, modifier in pairs(self.modifiers) do
        modifier.influence = value
    end
end

function Lab:setDebug(enabled)
    for _, modifier in pairs(self.modifiers) do
        modifier.debug = enabled
    end
end

function Lab:update(dt)
    self.time = self.time + dt
    local t = self.time
    -- The bot faces the camera (rotated 180 degrees), so its right arm is on the camera's left.
    self.red.position = { -22 + math.sin(t * 0.9) * 14, 62 + math.cos(t * 0.9) * 16, 12 + math.sin(t * 0.4) * 8 }
    self.blue.position = { 22 + math.sin(t * 0.7 + 1) * 10, 50 + math.cos(t * 1.1) * 14, 18 }
    self.floorMark.position = { 8 + math.sin(t * 0.6) * 10, 3, 24 + math.cos(t * 0.6) * 8 }
    self.scene.world:updateNodes(dt)
end

return Lab
