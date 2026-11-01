local Library = require('source.engine.physics.3d.backends.jolt.library')
local ffi, C = Library.ffi, Library.C

local Jobs = {}

ffi.cdef([[
typedef struct KP_Context KP_Context;
typedef struct { float friction, restitution; } KP_Material;
typedef struct {
    uint32_t a, subA, b, subB, added;
    float x, y, z;
} KP_Event;
typedef struct {
    JPH_RVec3 position;
    JPH_Quat rotation;
    JPH_Vec3 linear, angular;
} KP_State;
uint32_t KP_Install(void **functions);
void KP_QueueJob(void *, JPH_JobFunction *, void *);
void KP_QueueJobs(void *, JPH_JobFunction *, void **, uint32_t);
void KP_ReadBody(JPH_Body *, KP_State *);
KP_Context *KP_Create(uint32_t maxBodies);
uint32_t KP_SetBody(KP_Context *, uint32_t, const JPH_Shape *, const KP_Material *, uint32_t);
void KP_RemoveBody(KP_Context *, uint32_t);
uint32_t KP_Exclude(KP_Context *, uint32_t, uint32_t, uint32_t);
const KP_Event *KP_Events(KP_Context *);
size_t KP_Count(KP_Context *);
uint32_t KP_Failed(KP_Context *);
void KP_Clear(KP_Context *);
uint64_t KP_WorkerCallbacks(KP_Context *);
uint64_t KP_CallerCallbacks(KP_Context *);
void KP_Destroy(KP_Context *);
]])

local filenames = { Windows = 'katsa_jolt.dll', Linux = 'libkatsa_jolt.so' }
local filename = filenames[katsa.system.getOS()]
local path = filename
    and 'source/engine/physics/backends/jolt/native/' .. Library.platform .. '/' .. filename
if path and katsa.filesystem.getInfo(path) then
    local bytes = assert(katsa.filesystem.read(path))
    local hash = katsa.data.encode('string', 'hex', katsa.data.hash('sha256', bytes))
    local directory = 'native-cache/katsa-jolt-' .. hash
    assert(katsa.filesystem.createDirectory(directory))
    local target = directory .. '/' .. filename
    if katsa.filesystem.read(target) ~= bytes then
        assert(katsa.filesystem.write(target, bytes))
    end
    Jobs.C = ffi.load(katsa.filesystem.getSaveDirectory() .. '/' .. target)
    local names = {
        'JPH_Body_GetID',
        'JPH_ContactManifold_GetSubShapeID1',
        'JPH_ContactManifold_GetSubShapeID2',
        'JPH_ContactManifold_GetWorldSpaceNormal',
        'JPH_Shape_GetType',
        'JPH_CompoundShape_GetSubShapeIndexFromID',
        'JPH_ContactListener_SetProcs',
        'JPH_Body_GetPosition',
        'JPH_Body_GetRotation',
        'JPH_Body_GetLinearVelocity',
        'JPH_Body_GetAngularVelocity',
    }
    local functions = ffi.new('void *[?]', #names)
    for index, name in ipairs(names) do
        functions[index - 1] = ffi.cast('void *', C[name])
    end
    assert(Jobs.C.KP_Install(functions) == 1, 'Could not install native contact bridge')
end

local function synchronous(callbacks)
    local config = ffi.new('JPH_JobSystemConfig')
    config.queueJob = Jobs.C and Jobs.C.KP_QueueJob or callbacks.job
    config.queueJobs = Jobs.C and Jobs.C.KP_QueueJobs or callbacks.jobs
    config.maxConcurrency, config.maxBarriers = 1, 8
    return assert(C.JPH_JobSystemCallback_Create(config))
end

function Jobs.create(world, settings, callbacks)
    local requested = settings.workerThreads
    assert(
        requested == nil
            or type(requested) == 'number'
                and requested >= 0
                and requested <= 32
                and requested % 1 == 0,
        'workerThreads must be an integer from 0 to 32'
    )
    if Jobs.C then
        world.nativeContacts = assert(Jobs.C.KP_Create(settings.maxBodies or 16384))
        world.parallelThreshold = settings.parallelThreshold or 64
        world.workerThreads = requested
            or math.max(1, math.min(4, katsa.system.getProcessorCount() - 1))
        if world.workerThreads > 0 then
            world.serialJobs = synchronous(callbacks)
            return world.serialJobs
        end
    else
        assert(
            not requested or requested == 0,
            'Native parallel bridge unavailable on this platform'
        )
        world.workerThreads = 0
    end
    return synchronous(callbacks)
end

function Jobs.select(world)
    -- Small islands cost less than waking a worker pool; neither path changes solver settings.
    local parallel = world.workerThreads > 0
        and C.JPH_PhysicsSystem_GetNumActiveBodies(world.system, 0) >= world.parallelThreshold
    if parallel and not world.parallelJobs then
        local config = ffi.new('JobSystemThreadPoolConfig')
        config.maxJobs, config.maxBarriers, config.numThreads = 2048, 8, world.workerThreads
        world.parallelJobs = assert(C.JPH_JobSystemThreadPool_Create(config))
    end
    world.physics.stats.parallelStep = parallel
    return parallel and world.parallelJobs or world.jobs
end

function Jobs.syncBody(world, raw)
    if not world.nativeContacts then
        return
    end
    local shapes = raw._joltOwner.shapes
    if not world.materialCapacity or world.materialCapacity < #shapes then
        world.materialCapacity = math.max(4, #shapes * 2)
        world.materialBuffer = ffi.new('KP_Material[?]', world.materialCapacity)
    end
    local materials = world.materialBuffer
    for index, entry in ipairs(shapes) do
        materials[index - 1].friction = entry.raw:getFriction()
        materials[index - 1].restitution = entry.raw:getRestitution()
    end
    assert(
        Jobs.C.KP_SetBody(world.nativeContacts, raw._joltId, raw._joltShape, materials, #shapes)
            == 1,
        'Native material allocation failed'
    )
end

function Jobs.exclude(world, a, b, enabled)
    if world.nativeContacts then
        assert(
            Jobs.C.KP_Exclude(world.nativeContacts, a, b, enabled and 1 or 0) == 1,
            'Native collision exclusion allocation failed'
        )
    end
end

function Jobs.collect(world)
    local context = world.nativeContacts
    if not context then
        return
    end
    assert(Jobs.C.KP_Failed(context) == 0, 'Native contact event allocation failed')
    local count = tonumber(Jobs.C.KP_Count(context))
    local events = Jobs.C.KP_Events(context)
    for index = 0, count - 1 do
        local event = events[index]
        world:collectContact(
            tonumber(event.a),
            tonumber(event.subA),
            tonumber(event.b),
            tonumber(event.subB),
            event.added ~= 0,
            event.x,
            event.y,
            event.z
        )
    end
    Jobs.C.KP_Clear(context)
    world.physics.stats.workerThreads = world.workerThreads
    world.physics.stats.workerContactCallbacks = tonumber(Jobs.C.KP_WorkerCallbacks(context))
end

return Jobs
