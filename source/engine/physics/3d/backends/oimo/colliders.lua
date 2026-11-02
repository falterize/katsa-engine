-- Lua geometry is also the compatibility representation for Jolt debug/sensors.
local O = require('./types')
local Math = require('source.engine.math.math3d')
local Policy = require('../../internal.bodyPolicy')
local Contacts = require('./contacts')
local ipairs = require('source.engine.math.array').ipairs
local vec, valid = Policy.vec, Policy.valid
local Colliders = {}

function Colliders.add(body, collider)
    local self = body
    local p, u = self.physics, self.physics.units
    local scale = self.initialScale
    if collider.shape == 'Compound' then
        assert(collider.children and #collider.children > 0, 'Compound collider needs children')
        for _, child in ipairs(collider.children) do
            self:addCollider(child)
        end
        return
    end
    local sc = O.ShapeConfig.new()
    sc.density = collider.density or self.settings.density or 1
    sc.friction = collider.friction or self.settings.friction or 0.5
    sc.restitution = collider.restitution or self.settings.restitution or 0
    valid(sc.density, 'Collider3D.density', 0.00001)
    valid(sc.friction, 'Collider3D.friction', 0)
    valid(sc.restitution, 'Collider3D.restitution', 0)
    local shape = collider.shape or 'Box'
    local size = collider.size or self.object.size
    if shape == 'Box' then
        for i = 1, 3 do
            valid(size[i], 'Collider3D.size', 0.001)
        end
        sc.geometry = O.BoxGeometry.new(vec(size, 0.5 * scale / u))
    elseif shape == 'Sphere' then
        valid(collider.radius, 'Collider3D.radius', 0.001)
        sc.geometry = O.SphereGeometry.new(collider.radius * scale / u)
    elseif shape == 'Capsule' or shape == 'Cylinder' or shape == 'Cone' then
        valid(collider.radius, 'Collider3D.radius', 0.001)
        valid(collider.height, 'Collider3D.height', 0.001)
        local factory = shape == 'Capsule' and O.CapsuleGeometry
            or shape == 'Cylinder' and O.CylinderGeometry
            or O.ConeGeometry
        sc.geometry = factory.new(collider.radius * scale / u, collider.height * scale * 0.5 / u)
    elseif shape == 'Convex' then
        assert(
            collider.vertices and #collider.vertices >= 4,
            'Convex collider requires at least four non-coplanar vertices'
        )
        local vertices = {}
        for i, v in ipairs(collider.vertices) do
            vertices[i] = vec(v, scale / u)
        end
        sc.geometry = O.ConvexHullGeometry.new(O.array(vertices))
    elseif shape == 'Mesh' then
        -- Static triangle meshes exist only in the Jolt world. The Lua mirror is a tiny marker box
        -- at the mesh centre (it never collides) so debug and bookkeeping code keep a shape.
        assert(
            collider.vertices and #collider.vertices >= 3,
            'Mesh collider requires vertices {x,y,z}'
        )
        assert(
            collider.indices and #collider.indices >= 3 and #collider.indices % 3 == 0,
            'Mesh collider requires triangle indices (1-based, three per triangle)'
        )
        assert(self.type == 'Static', 'Mesh colliders are static-only')
        local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
        for _, v in ipairs(collider.vertices) do
            for axis = 1, 3 do
                min[axis] = math.min(min[axis], v[axis])
                max[axis] = math.max(max[axis], v[axis])
            end
        end
        collider = setmetatable({
            position = {
                (min[1] + max[1]) * 0.5,
                (min[2] + max[2]) * 0.5,
                (min[3] + max[3]) * 0.5,
            },
            _meshMirror = true,
        }, { __index = collider })
        sc.geometry = O.BoxGeometry.new(vec({ 0.01, 0.01, 0.01 }, 1 / u))
    else
        error('Unsupported collider shape: ' .. tostring(shape))
    end
    if collider.position then
        sc.position = vec(collider.position, scale / u)
    end
    if collider.rotation then
        local m = Math.compose({ 0, 0, 0 }, collider.rotation, { 1, 1, 1 })
        sc.rotation = O.Mat3.new(m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11])
    end
    sc.collisionGroup = p.groups[self.group]
    sc.collisionMask = (self.canCollide and self.colliderEnabled ~= false and not self.isTrigger)
            and p.masks[self.group]
        or 0
    if collider._meshMirror then
        sc.collisionMask = 0
    end
    sc.contactCallback = Contacts.create(self)
    local raw = O.Shape.new(sc)
    raw.userData = self
    self.shapes[#self.shapes + 1] = {
        raw = raw,
        collider = collider._meshMirror and getmetatable(collider).__index or collider,
    }
    self.raw:addShape(raw)
end

function Colliders.refreshFilters(body)
    local physics = body.physics
    for _, shape in ipairs(body.shapes) do
        shape.raw:setCollisionGroup(physics.groups[body.group])
        shape.raw:setCollisionMask(
            (body.canCollide and body.colliderEnabled ~= false and not body.isTrigger)
                    and physics.masks[body.group]
                or 0
        )
    end
end

return Colliders
