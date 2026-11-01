local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Policy = require('source.engine.physics.3d.internal.bodyPolicy')
local vec, valid, types, observedProperties =
    Policy.vec, Policy.valid, Policy.types, Policy.observedProperties
local BodyProperties = {}

function BodyProperties.install(Physics, Body3D)
    function Body3D:set(values)
        if self.physics._stepping or self.physics._flushing or self.physics._querying then
            local copy = {}
            for key, value in pairs(values) do
                copy[key] = value
            end
            self.physics.pendingSettings = self.physics.pendingSettings or {}
            table.insert(self.physics.pendingSettings, { body = self, values = copy })
            return
        end
        if values.type then
            assert(types[values.type] ~= nil, 'Unknown body type')
        end
        if values.isTrigger ~= nil then
            self.isTrigger = values.isTrigger == true
            -- Keep disabled sensors until their pending exit events have been processed.
            self.physics.triggerBodies[self] = true
        end
        for key, value in pairs(values) do
            if key == 'density' or key == 'mass' then
                valid(value, 'Body3D.density', 0.00001)
            elseif
                key == 'friction'
                or key == 'restitution'
                or key == 'linearDamping'
                or key == 'angularDamping'
            then
                valid(value, 'Body3D.' .. key, 0)
            end
        end
        for key, value in pairs(values) do
            self.settings[key] = value
        end
        if values.collisionGroup then
            self.group = self.physics.collisionGroups:canonical(values.collisionGroup)
        end
        if values.canCollide ~= nil then
            self.canCollide = values.canCollide
        end
        if values.canQuery ~= nil then
            self.canQuery = values.canQuery
        end
        self:refreshFilters()
        for _, shape in ipairs(self.shapes) do
            if values.friction then
                shape.raw:setFriction(values.friction)
            end
            if values.restitution then
                shape.raw:setRestitution(values.restitution)
            end
            if values.density then
                shape.raw:setDensity(values.density)
            end
        end
        if values.gravityScale then
            self.raw:setGravityScale(values.gravityScale)
        end
        if values.linearDamping then
            self.raw:setLinearDamping(values.linearDamping)
        end
        if values.angularDamping then
            self.raw:setAngularDamping(values.angularDamping)
        end
        if values.rotationFactor then
            self.raw:setRotationFactor(vec(values.rotationFactor, 1))
        end
        if values.autoSleep ~= nil then
            self.raw:setAutoSleep(values.autoSleep)
        end
        if values.type then
            assert(types[values.type] ~= nil, 'Unknown body type')
            self.type = values.type
            self.raw:setType(types[values.type])
        end
        if self.settings.mass and self.type == 'Dynamic' then
            self:setMass(self.settings.mass)
        end
        self.physics.adapter:applySettings(self, values)
        self.raw:wakeUp()
        if values.type and self._renderPose then
            self:resetRenderPose()
        end
        if self.object._independentBody then
            for key, value in pairs(values) do
                if key == 'type' then
                    self.object.bodyType = value
                else
                    self.object[key] = value
                end
            end
        end
    end

    function Body3D:setMass(value)
        valid(value, 'Body3D.mass', 0.00001)
        if self.physics._stepping or self.physics._flushing or self.physics._querying then
            return self:set({ mass = value })
        end
        assert(self.type == 'Dynamic', 'Custom mass requires a dynamic body')
        self.settings.mass = value
        local data = self.raw:getMassData()
        assert(data.mass > 0, 'Body3D collider must have positive volume before setting mass')
        data.localInertia:scaleEq(value / data.mass)
        data.mass = value
        self.raw:setMassData(data)
    end

    function Body3D:applyProperties()
        -- Observe all inputs before applying: a failed set must retry the complete
        -- delta, and unchanged bodies must not refresh filters or wake the solver.
        local delta = self._observedDelta or {}
        self._observedDelta = delta
        for key in pairs(delta) do
            delta[key] = nil
        end
        for _, key in ipairs(observedProperties) do
            local value = self.properties[key]
            if value ~= nil and self._propertySnapshot[key] ~= value then
                delta[key] = value
            end
        end
        if next(delta) then
            self:set(delta)
            for key, value in pairs(delta) do
                self._propertySnapshot[key] = value
            end
        end
    end
end

return BodyProperties
