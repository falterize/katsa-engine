local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Base = require('./builders.rig')
local Mesh = require('source.engine.composition.mesh')

local Lab = {}
Lab.__index = Lab

function Lab.new(scene)
    local self = Base.new(scene)
    setmetatable(self, Lab)
    scene.world.byName.ModelLabFloor:destroy()
    scene.world.root:find('FloorPhysics', true):destroy()
    self.track:stop(0)
    self.animator.debugEnabled = false
    scene.camera.position = { 0, 140, -230 }
    scene.camera.rotation = { -15, 0, 0 }
    scene.camera.drawDistance = 1400
    self.tracks = {
        walk = self.animator:load('Demo Walk', { order = 0, weight = 0.5 }),
        idle = self.animator:load('Demo Idle', { order = 0, weight = 0.5 }),
        wave = self.animator:load('Demo Wave', { order = 1, fadeIn = 0.6, fadeOut = 0.6 }),
    }
    for name in pairs(self.model.byNodeName) do
        if name:find('LeftArm') or name:find('LeftForeArm') or name:find('LeftHand') then
            self.tracks.wave.boneMask[name] = 1
        end
    end
    self.tracks.walk:play()
    self.tracks.idle:play()
    self.tracks.wave:play()
    local w = scene.world

    local function body(name, p, size, kind, color)
        local n = w:create('Body3D', {
            name = name,
            position = p,
            bodyType = kind or 'Dynamic',
            friction = 0.25,
            restitution = 0.25,
        })
        w:create('Collider3D', { shape = 'Box', size = size }, n)
        Mesh.create(w, {
            name = name .. 'Visual',
            size = size,
            color = color or { 0.3, 0.65, 0.9 },
            surfaceAppearance = { colorMap = 'stone' },
        }, n)
        n:update(0)
        return n
    end
    self.practiceFloor = body('PracticeFloor', { 0, -6, 210 }, { 500, 12, 500 }, 'Static')
    self.ramp = body('RollingRamp', { 130, 40, 150 }, { 90, 8, 200 }, 'Static', { 0.6, 0.45, 0.2 })
    self.ramp.physics:teleport({ 130, 40, 150 }, { 20, 0, 0 })
    self.constraints = {}
    local names = {
        'BallSocketConstraint3D',
        'HingeConstraint3D',
        'PrismaticConstraint3D',
        'RopeConstraint3D',
        'SpringConstraint3D',
        'CylindricalConstraint3D',
        'UniversalConstraint3D',
        'RagdollConstraint3D',
        'WeldConstraint3D',
        'GenericConstraint3D',
    }
    for i, name in ipairs(names) do
        local x = -180 + (i - 1) % 5 * 65
        local z = 100 + math.floor((i - 1) / 5) * 150
        local anchor = body('Anchor' .. i, { x, 110, z }, { 8, 8, 8 }, 'Static')
        local weight = body(
            'Weight' .. i,
            { x + 8, 65, z },
            { 12, 22, 12 },
            'Dynamic',
            { 0.85, 0.3, 0.2 }
        )
        local a = w:create('Attachment3D', { name = 'AnchorPoint' .. i }, anchor)
        local b =
            w:create('Attachment3D', { name = 'WeightPoint' .. i, position = { 0, 35, 0 } }, weight)
        local c = w:create(name, {
            name = name,
            attachment0 = a,
            attachment1 = b,
            length = 12,
            upperLimit = 45,
            lowerLimit = -45,
            motorSpeed = 20,
            motorForce = 2,
        }, w.root)
        self.constraints[#self.constraints + 1] = c
    end
    self.rigBody = w:create('Body3D', {
        name = 'AnimatedRigBody',
        bodyType = 'Kinematic',
        position = { 35, 50, 50 },
        rotationFactor = {
            0,
            0,
            0,
        },
    })
    w:create(
        'Collider3D',
        { name = 'RigCapsule', shape = 'Capsule', radius = 10, height = 80 },
        self.rigBody
    )
    self.model.root.parent = self.rigBody
    self.model.root.position = { 0, -50, 0 }
    self.rigBody:update(0)
    if self.attachment then
        local p = self.attachment:getWorldPosition()
        local weight =
            w:create('Body3D', { name = 'HandRopeWeight', position = { p[1], p[2] - 20, p[3] } })
        w:create('Collider3D', { shape = 'Sphere', radius = 4 }, weight)
        Mesh.create(w, {
            name = 'HandRopeVisual',
            kind = 'sphere',
            size = { 8, 8, 8 },
            color = { 0.95, 0.55, 0.1 },
        }, weight)
        local endpoint = w:create('Attachment3D', { name = 'HandRopeEndpoint' }, weight)
        self.handRope = w:create('RopeConstraint3D', {
            name = 'AnimatedHandRope',
            attachment0 = self.attachment,
            attachment1 = endpoint,
            length = 25,
        })
    end
    self.dropCount = 0
    self:dropBalls()
    return self
end

function Lab:dropBalls()
    local w = self.scene.world
    for i = 1, 6 do
        self.dropCount = self.dropCount + 1
        local body = w:create('Body3D', {
            name = 'RollingBall' .. self.dropCount,
            position = { 110 + (i % 3) * 16, 85 + math.floor(i / 3) * 16, 95 },
            friction = 0.1,
            restitution = 0.35,
        })
        w:create('Collider3D', { shape = 'Sphere', radius = 6 }, body)
        Mesh.create(w, {
            name = 'RollingVisual' .. self.dropCount,
            kind = 'sphere',
            size = { 12, 12, 12 },
            color = {
                0.8,
                0.55,
                0.15,
            },
        }, body)
    end
end

return Lab
