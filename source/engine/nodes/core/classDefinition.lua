local ValueTypes = require('../../math.valueTypes')
local PropertyChanges = require('./propertyChanges')

local spatialKeys =
    { position = true, rotation = true, scale = true, size = true, spatialPosition = true }
local propertyAliases = require('./classPolicy').propertyAliases
local ClassDefinition = {}

function ClassDefinition.install(Node)
    function Node.define(name, base, registry)
        local classes = registry or Node.classes
        assert(
            type(name) == 'string' and not classes[name] and not Node.aliases[name],
            'Duplicate or invalid node class: ' .. tostring(name)
        )
        if type(base) == 'string' then
            base = Node.aliases[base] or base
        end
        base = type(base) == 'string'
                and assert(classes[base] or Node.classes[base], 'Unknown base class: ' .. base)
            or base
        local class = { name = name, base = base }
        class._types = { [name] = true }
        local ancestor = base
        while ancestor do
            class._types[ancestor.name] = true
            ancestor = ancestor.base
        end
        setmetatable(class, { __index = base })
        local spatial = class._types.Node3D
        local trackable = spatial or class._types.SurfaceAppearance3D
        class.instanceMetatable = {
            __index = function(instance, key)
                -- Internal cache misses still inherit private class defaults, but
                -- never need public property, alias or setter resolution.
                if type(key) == 'string' and key:byte() == 95 then
                    return class[key]
                end
                if spatial and spatialKeys[key] then
                    local typed = rawget(instance, '_typedValues')
                    local value = typed and typed[key]
                    if value ~= nil then
                        return value
                    end
                end
                local method = class[key]
                if type(method) == 'function' then
                    return method
                end
                if class.name == 'AnimationTrack' and key == 'priority' then
                    return instance.order
                end
                if propertyAliases[key] then
                    return instance[propertyAliases[key]]
                end
                local observed = trackable and rawget(instance, '_observedValues')
                if observed and observed[key] ~= nil then
                    return observed[key]
                end
                local typed = rawget(instance, '_typedValues')
                if typed and typed[key] ~= nil then
                    return typed[key]
                end
                local vectors = rawget(instance, '_billboardVectors')
                if vectors and vectors[key] then
                    return vectors[key]
                end
                if key == 'debug' and class.name == 'World2D' then
                    return instance.environment and instance.environment.debug
                end
                if key == 'TimeScale' then
                    return instance.timeScale
                end
                if key == 'Pixelate' then
                    return instance.pixelate
                end
                if
                    (key == 'currentCamera' or key == 'CurrentCamera')
                    and (class.name == 'World3D' or class.name == 'World2D')
                then
                    if class.name == 'World2D' then
                        return rawget(instance, '_currentCamera')
                    end
                    return instance._world and instance._world.activeCamera
                end
                if key == 'playing' and instance.setPlaying then
                    return rawget(instance, '_playing') or false
                end
                if key == 'enabled' and instance.getEnabled then
                    return instance:getEnabled()
                end
                if key == 'adornee' and instance.setAdornee then
                    return rawget(instance, '_adornee')
                end
                if key == 'parent' then
                    return rawget(instance, '_parent')
                end
                -- Live runtime state such as Body velocity: `class.computed[key] = {get, set}`.
                local computed = class.computed
                local entry = computed and computed[key]
                if entry then
                    return entry.get(instance)
                end
                return class[key]
            end,
            __newindex = function(instance, key, value)
                -- Engine cache writes never invoke authored vector conversion or setters.
                if type(key) == 'string' and key:byte() == 95 then
                    rawset(instance, key, value)
                    return
                end
                if class.name == 'AnimationTrack' and key == 'priority' then
                    key = 'order'
                end
                key = propertyAliases[key] or key
                local computed = class.computed
                local entry = computed and computed[key]
                if entry then
                    assert(entry.set, 'Property is read-only: ' .. tostring(key))
                    entry.set(instance, value)
                    return
                end
                if key == 'debug' and class.name == 'World2D' and instance.environment then
                    instance.environment.debug = value
                    return
                end
                if key == 'TimeScale' then
                    key = 'timeScale'
                end
                if key == 'Pixelate' then
                    key = 'pixelate'
                end
                local observed = trackable and rawget(instance, '_observedFields')
                if observed and observed[key] and key ~= 'parent' then
                    PropertyChanges.set(instance, key, value)
                    return
                end
                local typed = rawget(instance, '_typedValues')
                local kind = typed and ValueTypes.kind(instance, key)
                if kind then
                    ValueTypes.assign(instance, key, value, kind)
                    return
                end
                local vectors = rawget(instance, '_billboardVectors')
                if vectors and vectors[key] then
                    require('source.engine.core.validate').vector(value, 'BillboardUI.' .. key, 3)
                    assert(#value == 3, 'BillboardUI.' .. key .. ' requires three components')
                    local Managed = require('source.engine.math.managedValue')
                    Managed.unbind(vectors[key], instance)
                    vectors[key] = Managed.bind(
                        require('source.engine.math.vector3').fromArray(value),
                        instance
                    )
                    rawset(
                        instance,
                        '_propertyRevision',
                        (rawget(instance, '_propertyRevision') or 0) + 1
                    )
                    return
                end
                if
                    (key == 'currentCamera' or key == 'CurrentCamera')
                    and (class.name == 'World3D' or class.name == 'World2D')
                then
                    instance:setCurrentCamera(value)
                    return
                end
                if key == 'playing' and instance.setPlaying then
                    instance:setPlaying(value)
                    return
                end
                if key == 'enabled' and instance.setEnabled then
                    instance:setEnabled(value)
                    return
                end
                if key == 'adornee' and instance.setAdornee then
                    instance:setAdornee(value)
                elseif key == 'parent' then
                    instance:setParent(value)
                else
                    rawset(instance, key, value)
                end
            end,
        }
        classes[name] = class
        return class
    end
end

return ClassDefinition
