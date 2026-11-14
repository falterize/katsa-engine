local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local O = require('../valueTypes')
local Affine = require('source.engine.math.affine')
local bodyOf = require('source.engine.physics.bodyOf')
local Policy = require('./bodyPolicy')
local QueryPolicy = require('./queryPolicy')
local vec, valid = Policy.vec, Policy.valid
local Creation = {}

function Creation.install(Physics, Body3D)
    function Physics.new(settings)
        settings = settings or {}
        local backendName, driver, backendFallback = Physics.backends.resolve(settings.backend)
        local units = settings.unitsPerMeter or 20
        valid(units, 'physics.unitsPerMeter', 0.001)
        local gravity =
            require('source.engine.world.gravity').options(settings, 3, { 0, -196.2, 0 })
        local self = setmetatable({
            units = units,
            fixedDelta = settings.fixedDelta or 1 / 60,
            maxSteps = settings.maxSteps or 12,
            maxTriggerPairs = settings.maxTriggerPairs or 2048,
            interpolate = settings.interpolate == true,
            triggerBodies = {},
            accumulator = 0,
            bodies = {},
            pendingAdds = {},
            pendingRemoves = {},
            groups = { default = 1 },
            masks = { default = -1 },
            _debugSettings = { enabled = false },
            paused = false,
            stats = { steps = 0, droppedTime = 0 },
            scratch = O.Vec3.new(),
            transform = O.Transform.new(),
            rotation = O.Mat3.new(),
            rayBegin = O.Vec3.new(),
            rayEnd = O.Vec3.new(),
            propertyDelta = {},
            ray = O.RayCastClosest.new(),
            gravity = gravity,
            backendName = backendName,
            backendFallback = backendFallback,
        }, Physics)
        valid(self.fixedDelta, 'physics.fixedDelta', 1 / 1000)
        valid(self.maxSteps, 'physics.maxSteps', 1)
        assert(self.maxSteps % 1 == 0, 'maxSteps must be an integer')
        valid(self.maxTriggerPairs, 'physics.maxTriggerPairs', 1)
        assert(self.maxTriggerPairs % 1 == 0, 'maxTriggerPairs must be an integer')
        assert(
            settings.workerThreads == nil
                or type(settings.workerThreads) == 'number'
                    and settings.workerThreads >= 0
                    and settings.workerThreads <= 32
                    and settings.workerThreads % 1 == 0,
            'workerThreads must be an integer from 0 to 32'
        )
        assert(
            settings.parallelThreshold == nil
                or type(settings.parallelThreshold) == 'number'
                    and settings.parallelThreshold >= 0
                    and settings.parallelThreshold < math.huge
                    and settings.parallelThreshold % 1 == 0,
            'parallelThreshold must be a nonnegative integer'
        )
        if settings.maxBodies ~= nil then
            valid(settings.maxBodies, 'physics.maxBodies', 1)
            assert(
                settings.maxBodies <= 4194304 and settings.maxBodies % 1 == 0,
                'maxBodies must be an integer no greater than 4194304'
            )
        end
        self.adapter = driver.new(self, settings)
        self.world = self.adapter.world
        self.collisionGroups = require('source.engine.core.groups').new(function(registry)
            self.groups, self.masks = registry.bits, registry.masks
            for _, body in ipairs(self.bodies) do
                if registry.renamed and body.group == registry.renamed[1] then
                    body.group = registry.renamed[2]
                end
                if not registry.bits[body.group] then
                    body.group = 'Default'
                end
                body.settings.collisionGroup = body.group
                if body.node._independentBody then
                    body.node.collisionGroup = body.group
                end
                body:refreshFilters()
            end
        end)
        self.groups, self.masks = self.collisionGroups.bits, self.collisionGroups.masks
        self.ray.process = function(_, shape, hit)
            local body = shape.userData
            if QueryPolicy.accepts(self, body) and hit.fraction < self.ray.fraction then
                self.ray.hit = true
                self.ray.shape = shape
                self.ray.fraction = hit.fraction
                self.ray.position:copyFrom(hit.position)
                self.ray.normal:copyFrom(hit.normal)
            end
        end
        self.world:setNumVelocityIterations(settings.velocityIterations or 8)
        self.world:setNumPositionIterations(settings.positionIterations or 3)
        return self
    end

    function Physics:addGroup(name)
        return self.collisionGroups:add(name)
    end

    function Physics:setGroupsCollidable(a, b, enabled)
        self:addGroup(a)
        self:addGroup(b)
        self.collisionGroups:set(a, b, enabled)
    end

    -- Backend-native body -> physics object / node; nil when the body is not one of ours.
    function Physics:physicsOf(raw)
        return self._rawBodies and self._rawBodies[raw]
    end

    function Physics:nodeOf(raw)
        local body = self:physicsOf(raw)
        return body and body.node
    end

    function Physics:addBody(object, settings)
        assert(
            not self.released and not self._releasePending,
            'Cannot add bodies to a released Physics world'
        )
        settings = settings or {}
        assert(not bodyOf(object), 'Object already has a rigid body')
        local owner = object.parent
        while owner and owner:isA('Folder') do
            owner = owner.parent
        end
        assert(
            object._independentBody or not owner or owner.className == 'World3D',
            'Rigid bodies require World3D space; organizational Folders are allowed'
        )
        local scale = object.scale[1]
        assert(
            scale > 1e-6
                and math.abs(object.scale[2] - scale) < 1e-6
                and math.abs(object.scale[3] - scale) < 1e-6,
            'Rigid bodies support positive uniform scale at creation; nonuniform scale is '
                .. 'unsupported'
        )
        if owner and not object._independentBody then
            local matrix = owner:getWorldMatrix()
            for i = 1, 16 do
                local expected = (i == 1 or i == 6 or i == 11 or i == 16) and 1 or 0
                assert(
                    math.abs(matrix[i] - expected) < 1e-6,
                    'Physics requires an untransformed World3D root'
                )
            end
        end
        local m = object:getWorldMatrix()
        if object._independentBody then
            local _, _, ws = Affine.decompose(m)
            for i = 1, 3 do
                assert(
                    math.abs(ws[i] - scale) < 1e-6,
                    'Body3D requires a rigid, unscaled spatial parent'
                )
            end
        end
        local body = setmetatable({
            space = self,
            initialScale = scale,
            initialSize = { unpack(object.size) },
            node = object,
            settings = settings,
            type = settings.type or 'Dynamic',
            shapes = {},
            contacts = {},
            isTrigger = settings.isTrigger == true,
            raw = self.adapter:createBody(object, settings, scale),
            group = self.collisionGroups:canonical(settings.collisionGroup or 'Default'),
            canCollide = settings.canCollide ~= false,
            canQuery = settings.canQuery ~= false,
            collisionLevel = settings.collisionLevel or 'Bounding Box',
        }, Body3D)
        self:addGroup(body.group)
        body.properties = settings
        body._propertySnapshot = {}
        self.adapter:wrapBody(body)
        body:addCollider(settings.collider or { shape = 'Box', size = object.size })
        body.raw:setGravityScale(settings.gravityScale or 1)
        if settings.mass then
            body:setMass(settings.mass)
        end
        if settings.rotationFactor then
            body.raw:setRotationFactor(vec(settings.rotationFactor, 1))
        end
        if settings.velocity then
            body:setVelocity(settings.velocity)
        end
        if settings.angularVelocity then
            body.raw:setAngularVelocity(vec(settings.angularVelocity, 1))
        end
        self.bodies[#self.bodies + 1] = body
        if self._stepping or self._flushing or self._querying then
            self.pendingAdds[#self.pendingAdds + 1] = body
        else
            self.world:addRigidBody(body.raw)
            body._inWorld = true
        end
        if body.isTrigger then
            self.triggerBodies[body] = true
        end
        self._rawBodies = self._rawBodies or setmetatable({}, { __mode = 'k' })
        self._rawBodies[body.raw] = body
        object.physics = body
        object:onDestroy(function()
            body:destroy()
        end)
        body:sync()
        return body
    end
end

return Creation
