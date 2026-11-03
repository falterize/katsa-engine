-- Jolt owns simulation; Oimo helpers supply only Lua compatibility geometry.
-- Native calls synchronously re-enter Lua. Keep this bridge outside JIT traces.
if jit then
    jit.off(true, true)
end
local ipairs = require('source.engine.math.array').ipairs
local Library = require('./library')
local Compatibility = require('../oimo.compatibility')
local O = require('../oimo.types')
local Extensions = require('source.engine.core.extensions')
local Runtime = require('./runtime')
local NativeMath = require('./nativeMath')
local Contacts = require('./contacts')
local Jobs = require('./native.jobs')

local ffi, C = Library.ffi, Library.C

local World = setmetatable({}, { __index = Compatibility })
World.__index = World
local worlds = Runtime.worlds
local vector = NativeMath.vector

local callbacks = Contacts.callbacks
World._contactProcs, World._callbacks = Contacts.procs, callbacks
Extensions.apply(World, Contacts)
Extensions.apply(World, require('./queries'))
Extensions.apply(World, require('./filters'))
Extensions.apply(World, require('./colliders'))
Extensions.apply(World, require('./bodyBridge'))
Extensions.apply(World, require('./bodies'))
Extensions.apply(World, require('./constraints'))

function World.liveWorldCount()
    local count = 0
    for _ in pairs(worlds) do
        count = count + 1
    end
    return count
end

function World.new(physics, settings)
    local token = Runtime.nextToken()
    local self = setmetatable({
        physics = physics,
        poseEpoch = 0,
        token = token,
        byId = {},
        bodies = {},
        contacts = {},
        events = {},
        joints = {},
        noCollision = {},
        shadow = O.World.new(2, O.Vec3.new()),
        v1 = ffi.new('JPH_Vec3'),
        v2 = ffi.new('JPH_Vec3'),
        q = ffi.new('JPH_Quat'),
        matrix = ffi.new('JPH_Mat4'),
        mass = ffi.new('JPH_MassProperties'),
        oPosition = O.Vec3.new(),
        oRotation = O.Mat3.new(),
        oQuat = O.Quat.new(),
        bounds = ffi.new('JPH_AABox'),
        raySettings = ffi.new('JPH_RayCastSettings'),
        subshapeRemainder = ffi.new('JPH_SubShapeID[1]'),
        lambda2 = ffi.new('float[2]'),
    }, World)
    self.world = self
    physics.driver = self -- Compatibility alias for existing diagnostics.
    local broad = C.JPH_BroadPhaseLayerInterfaceTable_Create(64, 1)
    for i = 0, 63 do
        C.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broad, i, 0)
    end
    self.pairs = C.JPH_ObjectLayerPairFilterTable_Create(64)
    -- The broadphase filter precomputes a conservative table at construction.
    -- Enable every collidable layer first; the live pair filter refines masks.
    for i = 0, 31 do
        for j = i, 31 do
            C.JPH_ObjectLayerPairFilterTable_EnableCollision(self.pairs, i, j)
        end
    end
    local filter = C.JPH_ObjectVsBroadPhaseLayerFilterTable_Create(broad, 1, self.pairs, 64)
    local config = ffi.new('JPH_PhysicsSystemSettings')
    config.maxBodies, config.maxBodyPairs, config.maxContactConstraints =
        settings.maxBodies or 16384, 65536, 16384
    config.broadPhaseLayerInterface, config.objectLayerPairFilter, config.objectVsBroadPhaseLayerFilter =
        broad, self.pairs, filter
    self.system = assert(C.JPH_PhysicsSystem_Create(config))
    self.interface = C.JPH_PhysicsSystem_GetBodyInterface(self.system)
    self.narrow, self.broad =
        C.JPH_PhysicsSystem_GetNarrowPhaseQuery(self.system),
        C.JPH_PhysicsSystem_GetBroadPhaseQuery(self.system)
    self.jobs = Jobs.create(self, settings, callbacks)
    worlds[self.token] = self
    self.listener =
        C.JPH_ContactListener_Create(self.nativeContacts or ffi.cast('void*', self.token))
    C.JPH_PhysicsSystem_SetContactListener(self.system, self.listener)
    self:setGravity(
        O.Vec3.new(
            physics.gravity[1] / physics.units,
            physics.gravity[2] / physics.units,
            physics.gravity[3] / physics.units
        )
    )
    self.settings = ffi.new('JPH_PhysicsSettings')
    C.JPH_PhysicsSystem_GetPhysicsSettings(self.system, self.settings)
    self:initializeQueries()
    return self
end

function World:setGravity(v)
    C.JPH_PhysicsSystem_SetGravity(self.system, vector(self.v1, v))
end

function World:setNumVelocityIterations(n)
    self.settings.numVelocitySteps = n
    C.JPH_PhysicsSystem_SetPhysicsSettings(self.system, self.settings)
end

function World:setNumPositionIterations(n)
    self.settings.numPositionSteps = n
    C.JPH_PhysicsSystem_SetPhysicsSettings(self.system, self.settings)
end

function World:getNumVelocityIterations()
    return tonumber(self.settings.numVelocitySteps)
end

function World:getNumPositionIterations()
    return tonumber(self.settings.numPositionSteps)
end

function World:getGravity()
    C.JPH_PhysicsSystem_GetGravity(self.system, self.v1)
    return O.Vec3.new(self.v1.x, self.v1.y, self.v1.z)
end

function World:checkCallbackError()
    if self.callbackError then
        local err = self.callbackError
        self.callbackError = nil
        error(err, 0)
    end
end

function World:step(dt)
    self:stepMotors(dt)
    local started = katsa.timer.getTime()
    local code = C.JPH_PhysicsSystem_Update(self.system, dt, 1, Jobs.select(self))
    self.physics.stats.nativeSolverMilliseconds = (katsa.timer.getTime() - started) * 1000
    self.poseEpoch = self.poseEpoch + 1
    assert(code == 0, 'Jolt capacity error: ' .. tonumber(code))
    Jobs.collect(self)
    self:checkBreaks(dt)
    self:checkCallbackError()
    self:dispatchEvents()
end

function World:setDebugDraw(draw)
    self.shadow:setDebugDraw(draw)
end

World.supportsDebugPoses = true

-- `poses` (optional) overrides the drawn pose of some bodies, for example with the interpolated
-- render pose. The mirror is invalidated afterwards so the next refresh restores the solver pose.
function World:debugDraw(poses)
    for raw in pairs(self.bodies) do
        self:refreshMirror(raw)
    end
    if poses then
        for _, entry in ipairs(poses) do
            local raw = entry.raw
            if raw._joltPtr then
                self.oPosition:init(entry.x, entry.y, entry.z)
                raw._nativeOriginal.setPosition(raw, self.oPosition)
                self.oQuat:init(entry.qx, entry.qy, entry.qz, entry.qw)
                self.oRotation:fromQuat(self.oQuat)
                raw._nativeOriginal.setRotation(raw, self.oRotation)
                raw._joltMirrorEpoch, raw._joltPoseCache = nil, nil
            end
        end
    end
    self.shadow:debugDraw()
end

function World:release()
    if not self.system then
        return
    end
    for joint in pairs(self.joints) do
        self:removeJoint(joint)
    end
    C.JPH_PhysicsSystem_SetContactListener(self.system, nil)
    C.JPH_PhysicsSystem_Destroy(self.system)
    C.JPH_ContactListener_Destroy(self.listener)
    C.JPH_JobSystem_Destroy(self.jobs)
    if self.parallelJobs then
        C.JPH_JobSystem_Destroy(self.parallelJobs)
        self.parallelJobs = nil
    end
    self.serialJobs = nil
    if self.nativeContacts then
        Jobs.C.KP_Destroy(self.nativeContacts)
        self.nativeContacts = nil
    end
    self.rayCallback:free()
    self.aabbCallback:free()
    worlds[self.token] = nil
    self.system, self.interface, self.byId, self.contacts, self.events = nil, nil, {}, {}, {}
end

if jit then
    jit.off(World.step, true)
    jit.off(World.rayCast, true)
    jit.off(World.aabbTest, true)
end

return World
