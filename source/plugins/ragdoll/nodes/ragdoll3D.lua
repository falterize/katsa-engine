-- Ragdoll3D: turns the humanoid model it sits under into a physical ragdoll and back. Place it
-- under a model instance (the node `Models.instantiate` returns); the scene needs
-- `plugins = { ragdoll = true }` and a Physics3D world.
--
--   local ragdoll = world:create('Ragdoll3D', { source = characterBody }, modelRoot)
--   ragdoll.active = true          -- capsules per limb take over the animated pose
--   ragdoll:getBody('Hips')        -- the Body3D of a segment; follow it with a camera
--   ragdoll.active = false         -- the animation drives the skeleton again
local Humanoid = require('../humanoid')
local Rig = require('../rig')
local ModelNode = require('../../ik.modelNode')
local Skeleton = require('../../ik.skeleton')

local Definition = {
    base = 'Node',
    properties = {
        active = {
            default = false,
            hint = 'On: the skeleton follows physical bodies. Off: the animation drives it.',
        },
        rig = { default = 'Humanoid', options = { 'Humanoid' }, hint = 'How the bones are grouped into segments.' },
        source = {
            default = nil,
            kind = 'node',
            nodeClass = 'Body3D',
            hint = 'Body whose velocity the ragdoll starts with (the character body).',
        },
        density = { default = 1, min = 0.01, hint = 'Mass per volume of every segment.' },
        friction = { default = 0.8, min = 0, max = 4, hint = 'Surface friction of the segments.' },
        damping = { default = 0.15, min = 0, max = 10, hint = 'Linear and angular damping: higher settles sooner.' },
        thickness = { default = 0.22, min = 0.05, max = 0.5, hint = 'Capsule radius as a fraction of the segment length.' },
        jointLimit = { default = 55, min = 0, max = 180, hint = 'Swing and twist limit of the joints in degrees (scaled per joint).' },
        priority = { default = 100, hint = 'Order among the modifiers of one model; lower runs first.' },
        status = { default = '', readOnly = true, hint = 'Why the ragdoll could not start, if it could not.' },
    },
}

function Definition.initialize(self)
    self.status = ''
end

local function velocityOf(source)
    if source and source.physics and not source.destroyed then
        return source.physics:getVelocity({})
    end
end

-- Builds the bodies from the pose the skeleton has now.
function Definition:_start()
    local model = ModelNode.modelOf(self)
    local layout, message = Humanoid.resolve(model)
    if not layout then
        self.status = message
        self.active = false
        return
    end
    self._skeleton = Skeleton.new(model)
    self._rig = Rig.build(self, self._skeleton, layout, {
        density = self.density,
        friction = self.friction,
        damping = self.damping,
        thickness = self.thickness,
        limit = self.jointLimit,
        velocity = velocityOf(self.source),
    })
    self.status = ''
end

function Definition:_stop()
    self._rig:destroy()
    self._rig, self._skeleton = nil, nil
end

function Definition:update()
    -- The model can be instantiated after this node: keep looking until it is there.
    if not ModelNode.connect(self) then
        return
    end
    if self.active and not self._rig then
        self:_start()
    elseif not self.active and self._rig then
        self:_stop()
    end
end

-- Called by the Animator after sampling the pose.
function Definition:process()
    if self._rig then
        self._rig:drive(self._skeleton)
    end
end

-- The Body3D of a segment ('Hips', 'Chest', 'Head', 'UpperArmL', 'ShinR', ...), or nil while the
-- ragdoll is off.
function Definition:getBody(name)
    return self._rig and self._rig:getBody(name)
end

return Definition
