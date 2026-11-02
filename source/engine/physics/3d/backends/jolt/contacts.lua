-- Native callbacks can re-enter Lua; keep their prototypes out of JIT traces.
if jit then
    jit.off(true, true)
end

local Compatibility = require('../oimo.compatibility')
local Library = require('./library')
local NativeMath = require('./nativeMath')
local O = require('../oimo.types')
local ShapeLookup = require('./shapeLookup')
local Runtime = require('./runtime')
local Jobs = require('./native.jobs')

local C, ffi = Library.C, Library.ffi
local cast = NativeMath.cast
local shapeFor = ShapeLookup.resolve
local worlds = Runtime.worlds

local Contacts = {}
local Contact = {}
Contact.__index = Contact

function Contact:getShape1()
    return self.first
end

function Contact:getShape2()
    return self.second
end

function Contact:getManifold()
    return self
end

function Contact:getNormal()
    return self.normal
end

local function key(a, firstSubshape, b, secondSubshape)
    return a .. ':' .. firstSubshape .. ':' .. b .. ':' .. secondSubshape
end

local function guarded(user, fn, ...)
    local world = worlds[tonumber(ffi.cast('uintptr_t', user))]
    if not world then
        return
    end
    local ok, err = pcall(fn, world, ...)
    if not ok then
        world.callbackError = tostring(err)
    end
end
local procs = ffi.new('JPH_ContactListener_Procs')

function Contacts:bindContact(body, shape)
    Compatibility.bindContact(self, body, shape)
    self:bindMirror(body, shape)
end

function Contacts:collectContact(firstId, firstSubshape, secondId, secondSubshape, added, x, y, z)
    local world = self
    local id = key(firstId, firstSubshape, secondId, secondSubshape)
    local contact = world.contacts[id]
    if not added then
        if contact then
            world.contacts[id] = nil
            world.events[#world.events + 1] = { contact, false }
        end
        return
    end
    local first, second = world.byId[firstId], world.byId[secondId]
    if not first or not second then
        return
    end
    if not contact then
        contact = setmetatable({
            first = shapeFor(first, firstSubshape),
            second = shapeFor(second, secondSubshape),
            normal = O.Vec3.new(),
        }, Contact)
        world.contacts[id] = contact
        world.events[#world.events + 1] = { contact, true }
    end
    contact.normal:init(x, y, z)
    return contact
end

local function collectContact(world, a, b, manifold, settings)
    C.JPH_ContactManifold_GetWorldSpaceNormal(manifold, world.v1)
    local contact = world:collectContact(
        tonumber(C.JPH_Body_GetID(a)),
        tonumber(C.JPH_ContactManifold_GetSubShapeID1(manifold)),
        tonumber(C.JPH_Body_GetID(b)),
        tonumber(C.JPH_ContactManifold_GetSubShapeID2(manifold)),
        true,
        world.v1.x,
        world.v1.y,
        world.v1.z
    )
    if contact then
        settings.combinedFriction =
            math.sqrt(contact.first:getFriction() * contact.second:getFriction())
        settings.combinedRestitution =
            math.sqrt(contact.first:getRestitution() * contact.second:getRestitution())
    end
end
local callbacks = {}
callbacks.job = ffi.cast('JPH_QueueJobCallback*', function(_, fn, arg)
    fn(arg)
end)
callbacks.jobs = ffi.cast('JPH_QueueJobsCallback*', function(_, fn, args, count)
    for i = 0, tonumber(count) - 1 do
        fn(args[i])
    end
end)
callbacks.validate = ffi.cast(
    'JPH_ValidateResult (*)(void*, const JPH_Body*, const JPH_Body*, const JPH_RVec3*, const '
        .. 'JPH_CollideShapeResult*)',
    function(user, a, b)
        local world = worlds[tonumber(ffi.cast('uintptr_t', user))]
        local first, second = tonumber(C.JPH_Body_GetID(a)), tonumber(C.JPH_Body_GetID(b))
        if world and world.noCollision[first] and world.noCollision[first][second] then
            return 3
        end
        return 0
    end
)
callbacks.added = ffi.cast(
    'void (*)(void*, const JPH_Body*, const JPH_Body*, const JPH_ContactManifold*, '
        .. 'JPH_ContactSettings*)',
    function(user, a, b, manifold, settings)
        guarded(user, collectContact, a, b, manifold, settings)
    end
)
callbacks.removed = ffi.cast('void (*)(void*, const JPH_SubShapeIDPair*)', function(user, pair)
    guarded(user, function(world)
        local id = key(
            tonumber(pair.Body1ID),
            tonumber(pair.subShapeID1),
            tonumber(pair.Body2ID),
            tonumber(pair.subShapeID2)
        )
        local contact = world.contacts[id]
        if contact then
            world.contacts[id] = nil
            world.events[#world.events + 1] = { contact, false }
        end
    end)
end)
procs.OnContactValidate, procs.OnContactAdded, procs.OnContactRemoved =
    callbacks.validate, callbacks.added, callbacks.removed
procs.OnContactPersisted = callbacks.added
if not Jobs.C then
    C.JPH_ContactListener_SetProcs(procs)
end
-- joltc retains this pointer rather than copying the procedure table.
Contacts.procs, Contacts.callbacks = procs, callbacks

function Contacts:dispatchEvents()
    local events = self.events
    if #events == 0 or self._dispatching then
        return
    end
    -- Detach: contact callbacks can destroy bodies and append end events.
    self.events, self.spareEvents = self.spareEvents or {}, nil
    self._dispatching = true
    for _, event in ipairs(events) do
        local contact, begin = event[1], event[2]
        local a, b = contact.first:getContactCallback(), contact.second:getContactCallback()
        local method = begin and 'beginContact' or 'endContact'
        if a and a[method] then
            a[method](a, contact)
        end
        if b and b[method] then
            b[method](b, contact)
        end
    end
    for i = #events, 1, -1 do
        events[i] = nil
    end
    self.spareEvents = events
    self._dispatching = false
end

return Contacts
