-- Native callbacks can re-enter Lua; keep their prototypes out of JIT traces.
if jit then
    jit.off(true, true)
end

local QueryPolicy = require('source.engine.physics.3d.internal.queryPolicy')
local Library = require('source.engine.physics.3d.backends.jolt.library')
local NativeMath = require('source.engine.physics.3d.backends.jolt.nativeMath')
local ShapeLookup = require('source.engine.physics.3d.backends.jolt.shapeLookup')

local C, ffi = Library.C, Library.ffi
local vector, cast = NativeMath.vector, NativeMath.cast
local shapeFor = ShapeLookup.resolve

local Queries = {}

function Queries:initializeQueries()
    self.raySettings.treatConvexAsSolid = true
    self.rayCallback = ffi.cast('JPH_CastRayCollectorCallback*', function(_, hit)
        local ok, err = pcall(function()
            local raw = self.byId[tonumber(hit.bodyID)]
            if raw then
                local owner = raw._joltOwner
                if QueryPolicy.accepts(self.physics, owner) then
                    local ray = self.queryRay
                    if hit.fraction < ray.fraction then
                        ray.hit, ray.fraction, ray.shape =
                            true, hit.fraction, shapeFor(raw, hit.subShapeID2)
                        local f = hit.fraction
                        self.v2.x, self.v2.y, self.v2.z =
                            self.queryX + self.queryDX * f,
                            self.queryY + self.queryDY * f,
                            self.queryZ + self.queryDZ * f
                        ray.position:init(self.v2.x, self.v2.y, self.v2.z)
                        C.JPH_Body_GetWorldSpaceSurfaceNormal(
                            raw._joltPtr,
                            hit.subShapeID2,
                            self.v2,
                            self.v1
                        )
                        ray.normal:init(self.v1.x, self.v1.y, self.v1.z)
                    end
                end
            end
        end)
        if not ok then
            self.callbackError = tostring(err)
        end
        return self.queryRay.fraction
    end)
    self.aabbCallback = ffi.cast('JPH_CollideShapeBodyCollectorCallback*', function(_, id)
        local ok, err = pcall(function()
            local raw = self.byId[tonumber(id)]
            if raw then
                for _, shape in ipairs(raw._joltOwner.shapes) do
                    self.queryAabb:process(shape.raw)
                end
            end
        end)
        if not ok then
            self.callbackError = tostring(err)
        end
        return 1
    end)
end

function Queries:rayCast(a, b, ray)
    self.queryRay = ray
    self.queryX, self.queryY, self.queryZ = a.x, a.y, a.z
    self.queryDX, self.queryDY, self.queryDZ = b.x - a.x, b.y - a.y, b.z - a.z
    vector(self.v1, a)
    self.v2.x, self.v2.y, self.v2.z = self.queryDX, self.queryDY, self.queryDZ
    C.JPH_NarrowPhaseQuery_CastRay2(
        self.narrow,
        self.v1,
        self.v2,
        self.raySettings,
        self.rayCallback,
        nil,
        nil,
        nil,
        nil,
        nil
    )
    self.queryRay = nil
    self:checkCallbackError()
end

function Queries:aabbTest(box, callback)
    self.queryAabb = callback
    self.bounds.min.x, self.bounds.min.y, self.bounds.min.z = box._minX, box._minY, box._minZ
    self.bounds.max.x, self.bounds.max.y, self.bounds.max.z = box._maxX, box._maxY, box._maxZ
    C.JPH_BroadPhaseQuery_CollideAABox(self.broad, self.bounds, self.aabbCallback, nil, nil, nil)
    self.queryAabb = nil
    self:checkCallbackError()
end

return Queries
