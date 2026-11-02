local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Math = require('source.engine.math.math3d')
local Affine = require('source.engine.math.affine')
local BodyExtensions = {}

function BodyExtensions.install(Body3D, Physics, O)
    -- Velocity of the material point of this body at a world position (linear + angular x r),
    -- in world units per second. Something standing on a moving body is carried by this.
    function Body3D:getPointVelocity(position, out)
        out = out or {}
        self._pointPosition = self._pointPosition or O.Vec3.new()
        self._pointAngular = self._pointAngular or O.Vec3.new()
        self._pointVelocity = self._pointVelocity or {}
        local p, angular = self._pointPosition, self._pointAngular
        self.raw:getPositionTo(p)
        self.raw:getAngularVelocityTo(angular)
        local v, units = self:getVelocity(self._pointVelocity), self.physics.units
        local rx, ry, rz =
            position[1] - p.x * units, position[2] - p.y * units, position[3] - p.z * units
        out[1] = v[1] + (angular.y * rz - angular.z * ry)
        out[2] = v[2] + (angular.z * rx - angular.x * rz)
        out[3] = v[3] + (angular.x * ry - angular.y * rx)
        return out
    end

    function Body3D:pointResponse(position, axis)
        self._pointPosition = self._pointPosition or O.Vec3.new()
        self._pointAngular = self._pointAngular or O.Vec3.new()
        self._pointVelocity = self._pointVelocity or {}
        local p, angular = self._pointPosition, self._pointAngular
        self.raw:getPositionTo(p)
        self.raw:getAngularVelocityTo(angular)
        local v = self:getVelocity(self._pointVelocity)
        local rx, ry, rz =
            position[1] - p.x * self.physics.units,
            position[2] - p.y * self.physics.units,
            position[3] - p.z * self.physics.units
        local speed = (v[1] + angular.y * rz - angular.z * ry) * axis[1]
            + (v[2] + angular.z * rx - angular.x * rz) * axis[2]
            + (v[3] + angular.x * ry - angular.y * rx) * axis[3]
        if self.type ~= 'Dynamic' then
            return speed, 0
        end
        local x, y, z =
            (ry * axis[3] - rz * axis[2]) / self.physics.units,
            (rz * axis[1] - rx * axis[3]) / self.physics.units,
            (rx * axis[2] - ry * axis[1]) / self.physics.units
        return speed, self.physics.adapter:pointInverseMass(self, x, y, z)
    end

    function Body3D:_recordContact(other, contact, begin)
        self._contactSets = self._contactSets or {}
        local set = self._contactSets[other]
        if begin then
            if not set then
                set = {}
                self._contactSets[other] = set
            end
            set[contact] = true
            self.contacts[other] = contact
        elseif set then
            set[contact] = nil
            local remaining = next(set)
            self.contacts[other] = remaining
            if not remaining then
                self._contactSets[other] = nil
            end
        end
    end

    function Body3D:teleportLocal(position, rotation)
        if not self.object._independentBody then
            return self:teleport(position, rotation)
        end
        local localMatrix =
            Math.compose(position, rotation or self.object.rotation, self.object.scale)
        local parent = Affine.parentMatrix(self.object, self.object.parent)
        local p, r = Affine.decompose(parent and Math.multiply(parent, localMatrix) or localMatrix)
        return self:teleport(p, r)
    end

    function Body3D:getContacts()
        local result = {}
        for other in pairs(self.contacts) do
            if not other.destroyed then
                result[#result + 1] = other
            end
        end
        return result
    end

    function Body3D:setCollider(collider)
        assert(not self.destroyed, 'Cannot rebuild a destroyed body')
        -- Build every shape first so validation failure preserves the live collider.
        local candidate = setmetatable({
            physics = self.physics,
            initialScale = self.initialScale,
            object = self.object,
            settings = self.settings,
            type = self.type,
            group = self.group,
            canCollide = self.canCollide,
            isTrigger = self.isTrigger,
            raw = self.physics.adapter:createColliderCandidate(),
            shapes = {},
            contacts = {},
        }, Body3D)
        candidate:addCollider(collider)
        candidate.collider = collider
        self.physics.adapter:prepareCollider(candidate)
        if self.physics._stepping or self.physics._flushing or self.physics._querying then
            self.physics.pendingColliderChanges = self.physics.pendingColliderChanges or {}
            table.insert(
                self.physics.pendingColliderChanges,
                { body = self, candidate = candidate }
            )
        else
            self:_applyCollider(candidate)
        end
        return self
    end

    function Body3D:_applyCollider(candidate)
        local physics = self.physics
        local before = physics._flushing
        physics._flushing = true
        local ok, err = pcall(function()
            local old = self.shapes
            self.shapes = {}
            for _, shape in ipairs(old) do
                self.raw:removeShape(shape.raw)
            end
            if self.destroyed then
                return
            end
            for _, shape in ipairs(candidate.shapes) do
                candidate.raw:removeShape(shape.raw)
                shape.raw.userData = self
                -- Shape callbacks must refer to the live wrapper, not the validation body.
                physics.adapter:bindContact(self, shape.raw)
                self.shapes[#self.shapes + 1] = shape
                self.raw:addShape(shape.raw)
            end
            self.settings.collider = candidate.collider
            if self.settings.mass and self.type == 'Dynamic' then
                self:setMass(self.settings.mass)
            end
            self:refreshFilters()
            physics.adapter:rebuild(self, candidate)
            self.colliderRevision = (self.colliderRevision or 0) + 1
            self.raw:wakeUp()
        end)
        physics._flushing = before
        if not ok then
            error(err, 0)
        end
    end
end

return BodyExtensions
