local Mesh = require('source.engine.composition.mesh')
local Models = require('source.engine.import.models')

-- The XBot faces the camera and both hands follow a ball that floats in front of its chest. The
-- elbows bend toward hint markers beside and behind the body. Four InverseKinematics3D nodes do
-- the work: two arms (switchable between TwoBone, CCD, FABRIK and Jacobian), the head (LookAt)
-- and a spine tilt (LookAt chain), all driven by plain scene nodes.
local Lab = {}
Lab.__index = Lab

local PREFIX = 'mixamorig:'
Lab.armTypes = { 'TwoBone', 'CCD', 'FABRIK', 'Jacobian' }

local function distance(ax, ay, az, bx, by, bz)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

function Lab.new(scene)
    local IK = require('source.engine.plugins').require('ik')
    local self = setmetatable({ scene = scene, time = 0, armType = 1 }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.sky.enabled = false
    world.environment.ambient = { 160, 175, 190 }
    Mesh.create(world, {
        name = 'IKFloor',
        position = { 0, -3, 0 },
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
    local _, root = Models.instantiate(world, self.model, {
        name = 'IKBot',
        position = { 0, 0, 0 },
        rotation = { 0, 180, 0 },
        scale = { 0.55, 0.55, 0.55 },
    })
    self.root = root
    self.model.animator.debugEnabled = true
    -- Measure the rig once (rest pose) to place the ball, hints and camera.
    local skeleton = IK.Skeleton.new(self.model)
    local function worldOf(name)
        return { skeleton:toWorld(skeleton:getPosition(PREFIX .. name)) }
    end
    local right, left = worldOf('RightArm'), worldOf('LeftArm')
    local hand = worldOf('RightHand')
    local reach = distance(right[1], right[2], right[3], hand[1], hand[2], hand[3])
    self.reach = reach
    self.center = {
        (right[1] + left[1]) / 2,
        (right[2] + left[2]) / 2 - 0.2 * reach,
        (right[3] + left[3]) / 2 - 0.8 * reach,
    }
    local outward = right[1] > left[1] and 1 or -1
    scene.camera.position = { 0, self.center[2] + 0.1 * reach, self.center[3] - 1.9 * reach }
    scene.camera.rotation = { -3, 0, 0 }

    self.ball = Mesh.create(world, {
        name = 'IKBall',
        kind = 'sphere',
        size = { 0.4 * reach, 0.4 * reach, 0.4 * reach },
        color = { 1, 0.25, 0.2, 1 },
        position = self.center,
    })
    local function hint(name, shoulder, side)
        return Mesh.create(world, {
            name = name,
            size = { 0.1 * reach, 0.1 * reach, 0.1 * reach },
            color = { 0.9, 0.85, 0.2, 1 },
            position = {
                shoulder[1] + side * outward * 0.9 * reach,
                shoulder[2] - 0.7 * reach,
                shoulder[3] + 0.2 * reach,
            },
        })
    end
    self.rightHint = hint('RightElbowHint', right, 1)
    self.leftHint = hint('LeftElbowHint', left, -1)
    self.lookTarget = Mesh.create(world, {
        name = 'LookTarget',
        kind = 'sphere',
        size = { 0.05 * reach, 0.05 * reach, 0.05 * reach },
        color = { 1, 1, 1, 1 },
        position = self.center,
    })

    -- Each hand holds one side of the ball: the targets are children of the ball.
    local function grip(name, side)
        return world:create('Node3D', {
            name = name,
            position = { side * outward * 0.2 * reach, 0, 0 },
        }, self.ball)
    end
    self.rightGrip, self.leftGrip = grip('RightGrip', 1), grip('LeftGrip', -1)
    local function arm(side, hintNode, gripNode)
        return world:create('InverseKinematics3D', {
            name = side .. 'ArmIK',
            type = 'TwoBone',
            rootBone = PREFIX .. side .. 'Arm',
            tipBone = PREFIX .. side .. 'Hand',
            target = gripNode,
            pole = hintNode,
            softness = 0.5,
            iterations = 16,
            maxStep = 25,
            debug = true,
        }, root)
    end
    self.arms = {
        arm('Right', self.rightHint, self.rightGrip),
        arm('Left', self.leftHint, self.leftGrip),
    }
    self.head = world:create('InverseKinematics3D', {
        name = 'HeadIK',
        type = 'LookAt',
        rootBone = PREFIX .. 'Neck',
        tipBone = PREFIX .. 'Head',
        target = self.lookTarget,
        forward = { 0, 0, 1 },
        maxAngle = 60,
        smoothing = 8,
        debug = true,
    }, root)
    return self
end

function Lab:setArmType(index)
    self.armType = index
    for _, node in ipairs(self.arms) do
        node.type = Lab.armTypes[index]
    end
end

function Lab:setInfluence(value)
    for _, node in ipairs(self.arms) do
        node.influence = value
    end
    self.head.influence = value
end

function Lab:setDebug(enabled)
    for _, node in ipairs(self.arms) do
        node.debug = enabled
    end
    self.head.debug = enabled
end

function Lab:update(dt)
    self.time = self.time + dt
    local t, r, c = self.time, self.reach, self.center
    self.ball.position = {
        c[1] + math.sin(t * 0.9) * 0.35 * r,
        c[2] + math.sin(t * 1.8) * 0.2 * r,
        c[3] + math.sin(t * 0.45) * 0.12 * r,
    }
    self.lookTarget.position = { self.ball.position[1], c[2] + 0.55 * r, self.ball.position[3] }
    self.scene.world:updateNodes(dt)
end

return Lab
