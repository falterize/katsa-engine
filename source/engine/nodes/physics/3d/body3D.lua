local ipairs = require('source.engine.math.array').ipairs
local Node = require('../../core.baseNode')
local Snapshot = require('source.engine.core.valueSnapshot')

local Class = Node.define('Body3D', 'Node3D')

-- Live solver state, read and written through `node.physics` (docs/guides/physics/nodeAccess.md).
-- Before the body exists a written value is kept and handed to the body when it is created.
Class.computed = {
    velocity = {
        get = function(self)
            local body = rawget(self, 'physics')
            return body and body:getVelocity() or rawget(self, '_initialVelocity') or { 0, 0, 0 }
        end,
        set = function(self, value)
            local body = rawget(self, 'physics')
            if body then
                body:setVelocity(value)
            else
                rawset(self, '_initialVelocity', value)
            end
        end,
    },
    angularVelocity = {
        get = function(self)
            local body = rawget(self, 'physics')
            return body and body:getAngularVelocity()
                or rawget(self, '_initialAngularVelocity')
                or { 0, 0, 0 }
        end,
        set = function(self, value)
            local body = rawget(self, 'physics')
            if body then
                body:setAngularVelocity(value)
            else
                rawset(self, '_initialAngularVelocity', value)
            end
        end,
    },
    isSleeping = {
        get = function(self)
            local body = rawget(self, 'physics')
            return body ~= nil and body:isSleeping()
        end,
    },
}
Class.propertySchema = {
    velocity = { readOnly = true, get = Class.computed.velocity.get },
    angularVelocity = { readOnly = true, get = Class.computed.angularVelocity.get },
    isSleeping = { readOnly = true, get = Class.computed.isSleeping.get },
}

function Class.initialize(self)
    self._independentBody = true
    self.bodyType = self.bodyType or 'Dynamic'
    self.friction = self.friction or 0.5
    self.restitution = self.restitution or 0
    self.density = self.density or 1
    self.gravityScale = self.gravityScale or 1
    self.linearDamping = self.linearDamping or 0.05
    self.angularDamping = self.angularDamping or 0.05
    self.collisionGroup = self.collisionGroup or 'Default'
    self.isTrigger = self.isTrigger == true
    self.canQuery = self.canQuery ~= false
    self.canCollide = self.canCollide ~= false
    self.autoSleep = self.autoSleep ~= false
end

function Class.mount(world, properties, parent)
    assert(world.physics, 'Assign World3D.physics before creating Body3D nodes')
    local node = Node.new('Body3D', properties, parent)
    node._world = world
    local settings = {
        type = node.bodyType,
        collider = properties.collider or { shape = 'Box', size = node.size },
    }
    for _, key in ipairs({
        'mass',
        'autoSleep',
        'density',
        'friction',
        'restitution',
        'gravityScale',
        'linearDamping',
        'angularDamping',
        'canQuery',
        'canCollide',
        'isTrigger',
        'collisionGroup',
        'rotationFactor',
    }) do
        settings[key] = node[key]
    end
    settings.velocity = rawget(node, '_initialVelocity')
    settings.angularVelocity = rawget(node, '_initialAngularVelocity')
    world.physics:addBody(node, settings)
    node:setProcess(true)
    return node
end
local settingsKeys = {
    'autoSleep',
    'density',
    'friction',
    'restitution',
    'gravityScale',
    'linearDamping',
    'angularDamping',
    'canQuery',
    'canCollide',
    'isTrigger',
    'mass',
    'collisionGroup',
}

function Class:update(dt)
    if not self.physics or self.physics.destroyed then
        return
    end
    local inputs = self._settingsInputs or {}
    self._settingsInputs = inputs
    if
        Snapshot.fields(inputs, self, settingsKeys)
        or self._settingsPending
        or self.physics.type ~= self.bodyType
    then
        self._settingsPending = true
        local changes = self._settingsDelta or {}
        self._settingsDelta = changes
        for key in pairs(changes) do
            changes[key] = nil
        end
        local snapshot = self._bodySettings or {}
        self._bodySettings = snapshot
        for _, key in ipairs(settingsKeys) do
            local value = self[key]
            if value ~= nil and snapshot[key] ~= value then
                changes[key] = value
            end
        end
        if self.physics.type ~= self.bodyType then
            changes.type = self.bodyType
        end
        if next(changes) then
            self.physics:set(changes)
            for key, value in pairs(changes) do
                snapshot[key] = value
            end
        end
        self._settingsPending = false
    end
    -- Scratch belongs to this node; trim removed children to release descriptors.
    local descriptors, signature = self._colliderDescriptors or {}, self._colliderKeys or {}
    self._colliderDescriptors, self._colliderKeys = descriptors, signature
    local descriptorCount, keyCount = 0, 0
    local keysChanged = self._colliderKeysSignature == nil
    local explicit = false
    for _, node in ipairs(self.children) do
        if node:isA('Collider3D') then
            explicit = true
            if node.enabled then
                local descriptor, key = node:descriptor(self)
                if key then
                    keyCount = keyCount + 1
                    keysChanged = signature[keyCount] ~= key or keysChanged
                    signature[keyCount] = key
                end
                if descriptor then
                    descriptorCount = descriptorCount + 1
                    descriptors[descriptorCount] = descriptor
                end
            else
                keyCount = keyCount + 1
                local key = tostring(node) .. ':disabled'
                keysChanged = signature[keyCount] ~= key or keysChanged
                signature[keyCount] = key
            end
        end
    end
    keysChanged = #signature ~= keyCount or keysChanged
    for i = #signature, keyCount + 1, -1 do
        signature[i] = nil
    end
    for i = #descriptors, descriptorCount + 1, -1 do
        descriptors[i] = nil
    end
    local key = keysChanged and table.concat(signature, '|') or self._colliderKeysSignature
    self._colliderKeysSignature = key
    if self._collidersDirty or key ~= self._colliderSignature then
        if #descriptors > 0 then
            -- Body3D settings retain a persistent descriptor, never alias scratch.
            local children = {}
            for i = 1, descriptorCount do
                children[i] = descriptors[i]
            end
            self.physics:setCollider({ shape = 'Compound', children = children })
            self.physics.colliderEnabled = true
            self.physics:refreshFilters()
        elseif explicit or self._hadExplicitColliders then
            self.physics.colliderEnabled = false
            self.physics:refreshFilters()
        end
        self._hadExplicitColliders = self._hadExplicitColliders or explicit
        self._colliderSignature = key
        self._collidersDirty = false
    end
end

return Class
