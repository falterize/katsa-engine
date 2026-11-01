local Compatibility = require('source.engine.physics.3d.backends.oimo.compatibility')
local State = require('source.engine.physics.3d.backends.jolt.bodyState')
local Jobs = require('source.engine.physics.3d.backends.jolt.native.jobs')
local Library = require('source.engine.physics.3d.backends.jolt.library')
local NativeMath = require('source.engine.physics.3d.backends.jolt.nativeMath')

local C, ffi = Library.C, Library.ffi
local vector, cast = NativeMath.vector, NativeMath.cast

local quaternion = NativeMath.quaternion

local Colliders = {}

function Colliders:addCollider(body, collider)
    local count = #body.shapes
    Compatibility.addCollider(self, body, collider)
    for index = count + 1, #body.shapes do
        self:bindMirror(body, body.shapes[index].raw)
    end
end

function Colliders:bindMirror(body, shape)
    if shape._joltMirrorOwner == body then
        return
    end
    shape._joltMirrorOwner = body
    shape._joltGetAabb = shape._joltGetAabb or shape.getAabb
    shape._joltGetTransform = shape._joltGetTransform or shape.getTransform
    local getAabb, getTransform = shape._joltGetAabb, shape._joltGetTransform
    -- Only Lua narrow-phase/debug consumers need the Oimo representation's pose.
    shape.getAabb = function(value)
        self:refreshMirror(body.raw)
        return getAabb(value)
    end
    shape.getTransform = function(value)
        self:refreshMirror(body.raw)
        return getTransform(value)
    end
end

function Colliders:makeShape(body)
    local compound = C.JPH_StaticCompoundShapeSettings_Create()
    local scale = body.initialScale / self.physics.units
    local ok, result = pcall(function()
        for i, entry in ipairs(body.shapes) do
            local collider, shape = entry.collider
            local kind = collider.shape or 'Box'
            if kind == 'Box' then
                vector(self.v1, collider.size or body.object.size, scale * 0.5)
                shape = C.JPH_BoxShape_Create(
                    self.v1,
                    math.min(0.02, self.v1.x * 0.1, self.v1.y * 0.1, self.v1.z * 0.1)
                )
            elseif kind == 'Sphere' then
                shape = C.JPH_SphereShape_Create(collider.radius * scale)
            elseif kind == 'Capsule' then
                shape = C.JPH_CapsuleShape_Create(
                    collider.height * scale * 0.5,
                    collider.radius * scale
                )
            elseif kind == 'Cylinder' then
                local settings = C.JPH_CylinderShapeSettings_Create(
                    collider.height * scale * 0.5,
                    collider.radius * scale,
                    math.min(0.02, collider.radius * scale * 0.1, collider.height * scale * 0.05)
                )
                shape = C.JPH_CylinderShapeSettings_CreateShape(settings)
                C.JPH_ShapeSettings_Destroy(cast('ShapeSettings', settings))
            elseif kind == 'Convex' or kind == 'Cone' then
                local count = kind == 'Cone' and 25 or #collider.vertices
                local points = ffi.new('JPH_Vec3[?]', count)
                if kind == 'Cone' then
                    points[0].y = collider.height * scale * 0.5
                    for j = 1, 24 do
                        local a = j * math.pi / 12
                        points[j].x = math.cos(a) * collider.radius * scale
                        points[j].y = -collider.height * scale * 0.5
                        points[j].z = math.sin(a) * collider.radius * scale
                    end
                else
                    for j, v in ipairs(collider.vertices) do
                        vector(points[j - 1], v, scale)
                    end
                end
                local settings = C.JPH_ConvexHullShapeSettings_Create(points, count, 0)
                shape = C.JPH_ConvexHullShapeSettings_CreateShape(settings)
                C.JPH_ShapeSettings_Destroy(cast('ShapeSettings', settings))
            else
                error('Jolt unsupported collider: ' .. kind)
            end
            assert(shape ~= nil, 'Jolt rejected ' .. kind .. ' collider')
            C.JPH_ConvexShape_SetDensity(cast('ConvexShape', shape), entry.raw:getDensity())
            vector(self.v1, collider.position or { 0, 0, 0 }, scale)
            if collider.rotation then
                local m = require('source.engine.math.math3d').compose(
                    { 0, 0, 0 },
                    collider.rotation,
                    { 1, 1, 1 }
                )
                self.oRotation:init(m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11])
                quaternion(self.q, self.oRotation, self.oQuat)
            else
                self.q.x, self.q.y, self.q.z, self.q.w = 0, 0, 0, 1
            end
            C.JPH_CompoundShapeSettings_AddShape2(
                cast('CompoundShapeSettings', compound),
                self.v1,
                self.q,
                cast('Shape', shape),
                i - 1
            )
            C.JPH_Shape_Destroy(cast('Shape', shape))
        end
        return C.JPH_StaticCompoundShape_Create(compound)
    end)
    C.JPH_ShapeSettings_Destroy(cast('ShapeSettings', compound))
    assert(ok, result)
    assert(result ~= nil, 'Jolt compound collider construction failed')
    return cast('Shape', result)
end

function Colliders:prepareCollider(candidate)
    candidate._joltCandidateShape = ffi.gc(self:makeShape(candidate), C.JPH_Shape_Destroy)
end

function Colliders:rebuild(body, candidate)
    local raw = body.raw
    if not raw._joltPtr then
        return
    end
    local shape = candidate and candidate._joltCandidateShape or self:makeShape(body)
    if candidate and candidate._joltCandidateShape then
        ffi.gc(shape, nil)
        candidate._joltCandidateShape = nil
    end
    C.JPH_BodyInterface_SetShape(self.interface, raw._joltId, shape, true, 0)
    C.JPH_Shape_Destroy(raw._joltShape)
    raw._joltShape = shape
    State.invalidate(raw)
    raw._joltPoseCache = nil
    C.JPH_Body_SetFriction(raw._joltPtr, body.shapes[1].raw:getFriction())
    C.JPH_Body_SetRestitution(raw._joltPtr, body.shapes[1].raw:getRestitution())
    Jobs.syncBody(self, raw)
    self:restoreMass(body)
end

function Colliders:applySettings(body, values)
    local raw = body.raw
    if not raw._joltPtr then
        return
    end
    if values.friction ~= nil then
        C.JPH_Body_SetFriction(raw._joltPtr, values.friction)
    end
    if values.restitution ~= nil then
        C.JPH_Body_SetRestitution(raw._joltPtr, values.restitution)
    end
    if values.density ~= nil then
        -- Rebuilding recomputes per-child mass/inertia as well as density.
        local shape = self:makeShape(body)
        C.JPH_BodyInterface_SetShape(self.interface, raw._joltId, shape, true, 0)
        C.JPH_Shape_Destroy(raw._joltShape)
        raw._joltShape = shape
        State.invalidate(raw)
        raw._joltPoseCache = nil
    end
    if values.friction ~= nil or values.restitution ~= nil or values.density ~= nil then
        Jobs.syncBody(self, raw)
    end
    self:restoreMass(body)
    self:refreshFilters(body)
end

return Colliders
