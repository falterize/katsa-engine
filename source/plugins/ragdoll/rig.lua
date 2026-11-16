-- The physical side of a ragdoll: one capsule Body3D per segment, a RagdollConstraint3D per joint,
-- and the step that copies the bodies back into the skeleton.
--
--   local rig = Rig.build(owner, skeleton, layout, settings)  -- from the pose the skeleton has now
--   rig:drive(skeleton)                                        -- every pose evaluation
--   rig:destroy()
--
-- The layout comes from `humanoid.lua`; `settings` has density, friction, damping, thickness,
-- limit (degrees) and velocity ({x, y, z} the bodies start with).
local Quat = require('../ik.quat')
local Pose = require('./pose')

local Rig = {}
Rig.__index = Rig

local TWIST_TO_BONE = Quat.axisAngle(0, 0, 1, math.pi / 2, {}) -- joint frames: X axis along Y

local function lerp(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function boneWorld(skeleton, bone)
    return { Pose.position(skeleton, bone) }
end

local function firstChildBone(model, bone)
    for _, index in ipairs(bone.children or {}) do
        local child = model.nodes[index + 1]
        if child and child.isBone then
            return child
        end
    end
end

-- Where the segment ends: its next bone (`reach` of the way), the first child bone, or a stub
-- continuing the parent's direction.
local function finishPoint(skeleton, segment, start)
    local bone = segment.endBone or firstChildBone(skeleton.model, segment.bone)
    if bone then
        return lerp(boneWorld(skeleton, segment.bone), boneWorld(skeleton, bone), segment.reach)
    end
    local parent = segment.parent
    local d = parent and { start[1] - parent.start[1], start[2] - parent.start[2], start[3] - parent.start[3] }
        or { 0, 0.2, 0 }
    return { start[1] + d[1] * 0.5, start[2] + d[2] * 0.5, start[3] + d[3] * 0.5 }
end

local function distance(a, b)
    return math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
end

-- Creates the body of one segment lying from segment.start to segment.finish.
local function createBody(owner, segment, settings)
    local a, b = segment.start, segment.finish
    local length = math.max(distance(a, b), 1e-3)
    local radius = math.min(length * settings.thickness * segment.girth, length * 0.45)
    segment.rotation = Quat.fromTo(0, 1, 0, b[1] - a[1], b[2] - a[2], b[3] - a[3], {})
    segment.center = lerp(a, b, 0.5)
    segment.body = owner._sceneWorld:create('Body3D', {
        name = owner.name .. segment.name,
        position = segment.center,
        rotation = Pose.euler(segment.rotation),
        density = settings.density,
        friction = settings.friction,
        linearDamping = settings.damping,
        angularDamping = settings.damping,
        autoSleep = false,
        collider = {
            shape = 'Capsule',
            radius = radius,
            height = math.max(length - 2 * radius, 1e-3),
        },
    }) -- world space: the owner sits under a (possibly scaled) model
    if settings.velocity then
        segment.body.velocity = settings.velocity
    end
end

-- An attachment at the world point `joint`, local to `segment`'s body, with the joint frame
-- (`frame` a world rotation) applied.
local function attach(owner, segment, joint, frame, name)
    local inverse = Quat.conjugate(segment.rotation, {})
    local c = segment.center
    local x, y, z = Quat.rotate(inverse, joint[1] - c[1], joint[2] - c[2], joint[3] - c[3])
    return owner._sceneWorld:create('Attachment3D', {
        name = name,
        position = { x, y, z },
        rotation = Pose.euler(Quat.multiply(inverse, frame, {})),
    }, segment.body)
end

local function createJoint(owner, segment, settings)
    local parent = segment.parent
    local joint = segment.start
    local frame = Quat.multiply(segment.rotation, TWIST_TO_BONE, {})
    local limit = settings.limit * segment.limit
    segment.joint = owner._sceneWorld:create('RagdollConstraint3D', {
        name = segment.name .. 'Joint',
        attachment0 = attach(owner, parent, joint, frame, segment.name .. 'Parent'),
        attachment1 = attach(owner, segment, joint, frame, segment.name .. 'Child'),
        lowerLimit = -limit,
        upperLimit = limit,
        allowCollision = false,
    }, owner)
end

function Rig.build(owner, skeleton, layout, settings)
    skeleton:refresh()
    local rootRotation = Pose.rootRotation(skeleton, {})
    local segments = layout.segments
    for _, segment in ipairs(segments) do
        local parent = segment.parent
        segment.start = segment.chain and parent.finish or boneWorld(skeleton, segment.bone)
        segment.finish = finishPoint(skeleton, segment, segment.start)
        createBody(owner, segment, settings)
        -- The bone relative to its body, so the body's motion carries the bone along.
        local inverse = Quat.conjugate(segment.rotation, {})
        segment.offsetRotation =
            Quat.multiply(inverse, Pose.rotation(skeleton, segment.bone, rootRotation), {})
        if parent then
            createJoint(owner, segment, settings)
        else
            local p, c = boneWorld(skeleton, segment.bone), segment.center
            segment.offsetPosition =
                { Quat.rotate(inverse, p[1] - c[1], p[2] - c[2], p[3] - c[3]) }
        end
    end
    return setmetatable({ segments = segments, byName = layout.byName }, Rig)
end

-- Copies the bodies into the skeleton: every segment's bone takes its body's rotation, and the
-- root bone also its position (the other bones follow through their local offsets).
function Rig:drive(skeleton)
    skeleton:refresh()
    local rootRotation = Pose.rootRotation(skeleton, {})
    for _, segment in ipairs(self.segments) do
        local node = segment.body
        local rotation = Pose.nodeRotation(node)
        if segment.offsetPosition then
            local m = node:getRenderWorldMatrix()
            local o = segment.offsetPosition
            local x, y, z = Quat.rotate(rotation, o[1], o[2], o[3])
            skeleton:setPosition(segment.bone, skeleton:toModel(m[4] + x, m[8] + y, m[12] + z))
        end
        Pose.setRotation(
            skeleton,
            segment.bone,
            Quat.multiply(rotation, segment.offsetRotation, {}),
            rootRotation
        )
    end
end

function Rig:getBody(name)
    local segment = self.byName[name]
    return segment and segment.body
end

function Rig:destroy()
    for i = #self.segments, 1, -1 do
        local segment = self.segments[i]
        if segment.joint then
            segment.joint:destroy()
        end
        segment.body:destroy()
    end
end

return Rig
