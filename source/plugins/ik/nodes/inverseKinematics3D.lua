-- InverseKinematics3D: one node, many solvers. Place it under a model instance (the node
-- `Models.instantiate` returns) and pick `type`; the inspector shows only the settings of that
-- type. The scene needs `plugins = { 'ik' }`.
--
--   local ik = world:create('InverseKinematics3D', {
--       type = 'TwoBone',
--       rootBone = 'mixamorig:RightArm', tipBone = 'mixamorig:RightHand',   -- mid = tip's parent
--       target = ball, pole = elbowHint,
--   }, botRoot)
--
-- Types: TwoBone (limbs), CCD, FABRIK, Jacobian (chains), Spline (chain follows the curve through
-- the node's Node3D children), LookAt (heads, turrets) and FK (angles instead of a target).
-- The node plugs into the model's Animator and runs after animation sampling every pose evaluation.
local Plugins = require('source.engine.plugins')

local TYPES = { 'TwoBone', 'CCD', 'FABRIK', 'Jacobian', 'Spline', 'LookAt', 'FK' }

local function only(...)
    return { key = 'type', oneOf = { ... } }
end

local function modelOf(node)
    local parent = node.parent
    while parent do
        if parent.model and parent.model.nodes then
            return parent.model
        end
        parent = parent.parent
    end
end

local function boneNames(node)
    local model = modelOf(node)
    if not model then
        return nil
    end
    local names = {}
    for _, bone in ipairs(model.nodes) do
        if bone.isBone then
            names[#names + 1] = bone.name
        end
    end
    return names
end

local Definition = {
    base = 'Node',
    properties = {
        type = {
            default = 'TwoBone',
            options = TYPES,
            hint = 'TwoBone: arm or leg. CCD / FABRIK / Jacobian: chains. Spline: chain follows a '
                .. 'curve. LookAt: aim bones at a target. FK: pose bones by angles.',
        },
        influence = { default = 1, min = 0, max = 1, hint = 'Blend between the animation (0) and the solved pose (1).' },
        priority = { default = 0, hint = 'Order among the modifiers of one model; lower runs first.' },
        debug = { default = false, hint = 'Draw the chain, target and pole over the 3D view.' },
        rootBone = { default = '', options = boneNames, hint = 'First bone of the chain (TwoBone: the upper arm or thigh).' },
        midBone = {
            default = '',
            options = boneNames,
            hint = 'Middle bone (elbow, knee). Empty = the parent of the tip bone.',
            visibleWhen = only('TwoBone'),
        },
        tipBone = { default = '', options = boneNames, hint = 'Last bone of the chain: the hand, foot, head or end effector.' },
        target = {
            default = nil,
            kind = 'node',
            nodeClass = 'Node3D',
            hint = 'Node the end of the chain reaches for or looks at.',
            visibleWhen = only('TwoBone', 'CCD', 'FABRIK', 'Jacobian', 'LookAt'),
        },
        pole = {
            default = nil,
            kind = 'node',
            nodeClass = 'Node3D',
            hint = 'Node the elbow / knee bends toward.',
            visibleWhen = only('TwoBone', 'FABRIK'),
        },
        softness = {
            default = 0,
            min = 0,
            hint = 'Model units over which the limb eases into full extension.',
            visibleWhen = only('TwoBone'),
        },
        iterations = {
            default = 10,
            min = 1,
            max = 64,
            hint = 'Solver passes per pose evaluation.',
            visibleWhen = only('CCD', 'FABRIK', 'Jacobian'),
        },
        tolerance = {
            default = 0.001,
            min = 0,
            hint = 'Stop when the tip is this close to the target (model units).',
            visibleWhen = only('CCD', 'FABRIK', 'Jacobian'),
        },
        maxStep = {
            default = 20,
            min = 0,
            hint = 'Largest rotation of one joint per iteration, in degrees (0 = unlimited for CCD).',
            visibleWhen = only('CCD', 'Jacobian'),
        },
        jointLimit = {
            default = 0,
            min = 0,
            max = 180,
            hint = 'How far a joint may leave the animated pose, in degrees (0 = unlimited).',
            visibleWhen = only('CCD', 'Jacobian'),
        },
        damping = {
            default = 0.2,
            min = 0,
            hint = 'Jacobian damping relative to the chain length; higher is steadier but slower.',
            visibleWhen = only('Jacobian'),
        },
        splineOffset = {
            default = 0,
            hint = 'Slides the chain along the curve (model units). The curve goes through the '
                .. 'Node3D children of this node, in order.',
            visibleWhen = only('Spline'),
        },
        forward = {
            default = { 0, 0, 1 },
            hint = 'Bone-local axis that should face the target.',
            visibleWhen = only('LookAt'),
        },
        maxAngle = {
            default = 0,
            min = 0,
            max = 180,
            hint = 'Largest turn away from the animated facing, in degrees (0 = unlimited).',
            visibleWhen = only('LookAt'),
        },
        smoothing = {
            default = 0,
            min = 0,
            hint = 'Follow speed in 1/second; 0 turns instantly.',
            visibleWhen = only('LookAt'),
        },
        rotation = {
            default = { 0, 0, 0 },
            hint = 'Euler degrees (Z * Y * X) applied to every bone of the chain.',
            visibleWhen = only('FK'),
        },
        falloff = {
            default = 1,
            hint = 'Scale of the rotation per joint along the chain (0.8 curls a finger).',
            visibleWhen = only('FK'),
        },
        fkMode = {
            default = 'Additive',
            options = { 'Additive', 'FromRest' },
            hint = 'Additive turns the animated pose; FromRest ignores the animation.',
            visibleWhen = only('FK'),
        },
    },
}

-- Settings table for the solver of the current `type`, from the node's properties.
local function settings(node, skeleton)
    local kind = node.type
    local common = {
        influence = node.influence,
        enabled = node.enabled ~= false,
        priority = node.priority,
        debug = node.debug == true,
        target = node.target,
        pole = node.pole,
    }
    local tip = assert(node.tipBone ~= '' and node.tipBone, 'InverseKinematics3D needs tipBone')
    if kind == 'TwoBone' then
        common.tip = tip
        common.mid = node.midBone ~= '' and node.midBone or skeleton:parentName(tip, 1)
        common.root = node.rootBone ~= '' and node.rootBone or skeleton:parentName(tip, 2)
        common.softness = node.softness
        return common
    end
    local chain = skeleton:chain(node.rootBone, tip)
    common.bones = chain
    common.iterations = node.iterations
    common.tolerance = node.tolerance
    common.maxStep = node.maxStep > 0 and node.maxStep or nil
    common.limit = node.jointLimit
    common.damping = node.damping
    common.offset = node.splineOffset
    common.forward = node.forward
    common.maxAngle = node.maxAngle > 0 and node.maxAngle or nil
    common.speed = node.smoothing > 0 and node.smoothing or nil
    common.rotation = node.rotation
    common.falloff = node.falloff
    common.mode = node.fkMode
    if kind == 'Spline' then
        common.points = function()
            local points = {}
            for _, child in ipairs(node.children) do
                if child.getWorldPosition then
                    points[#points + 1] = child
                end
            end
            return points
        end
    end
    return common
end

local SOLVERS = {
    TwoBone = 'TwoBone',
    CCD = 'Ccd',
    FABRIK = 'Fabrik',
    Jacobian = 'Jacobian',
    Spline = 'Spline',
    LookAt = 'LookAt',
    FK = 'FK',
}

function Definition.initialize(self)
    self._solvers = {}
end

-- Finds the Animator of the model this node sits under and registers with it.
function Definition:_connect()
    if self.animator and not self.animator.destroyed then
        return true
    end
    local model = modelOf(self)
    local animator = model and (model.animator or model.controller)
    if animator and animator.addModifier then
        animator:addModifier(self)
        self.animator = animator
        if not self._connected then
            self._connected = true
            self:onDestroy(function()
                if self.animator then
                    self.animator:removeModifier(self)
                end
            end)
        end
        return true
    end
    return false
end

function Definition:update()
    -- The model can be instantiated after this node: keep looking until it is there.
    self:_connect()
end

-- Called by Animator after sampling the pose.
function Definition:process(animator, dt)
    local model = animator.model
    local skeleton = self._skeleton
    if not skeleton or skeleton.model ~= model then
        skeleton = require('source.plugins.ik.skeleton').new(model)
        self._skeleton = skeleton
    end
    local IK = Plugins.require('ik')
    local kind = self.type
    local class = IK[assert(SOLVERS[kind], 'Unknown IK type: ' .. tostring(kind))]
    local solver = self._solvers[kind]
    local values = settings(self, skeleton)
    if not solver then
        solver = class.new(values)
        self._solvers[kind] = solver
    else
        solver:read(values)
    end
    self._active = solver
    solver:process(animator, dt)
end

function Definition:drawDebug(camera, g)
    if self._active then
        self._active:drawDebug(camera, g)
    end
end

Definition.TYPES = TYPES

return Definition
