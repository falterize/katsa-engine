local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Inherited class descriptions keep public properties independent of cache layout.
local Schema = {}
local Fields = require('./schemaFields')
local groups, enum = Fields.groups, Fields.enum

function Schema.keys(target, fallback)
    if target._settingsKind == 'Particles' then
        return { 'wind', 'maxParticles', 'collisionBudget', 'fixedDelta', 'maxSteps' }
    end
    if target._settingsKind == 'Debug' then
        return { 'bones', 'wireframe', 'orientation3D' }
    end
    if target._settingsKind == 'World2DDebug' then
        return { 'orientation2D' }
    end
    if target._settingsKind == 'Physics2DDebug' then
        return { 'enabled', 'shapes', 'joints', 'centers', 'velocities', 'contacts' }
    end
    if target._settingsKind == 'Shadows' then
        local result = { 'mode', 'lightSize', 'softnessLimit', 'blockerSearchRadius' }
        for _, key in ipairs(fallback) do
            if
                key ~= 'mode'
                and key ~= 'lightSize'
                and key ~= 'softnessLimit'
                and key ~= 'blockerSearchRadius'
            then
                result[#result + 1] = key
            end
        end
        for i = #result, 1, -1 do
            if not Schema.visible(target, result[i]) then
                table.remove(result, i)
            end
        end
        return result
    end
    if target._settingsKind == 'Sky' then
        return { 'enabled', 'texture', 'pixelate', 'layout', 'yaw', 'color', 'brightness' }
    end
    if target.emitters and target.collisionBudget then
        return { 'wind', 'maxParticles', 'collisionBudget', 'fixedDelta', 'maxSteps' }
    end
    if target._inputKind == 'Joystick' then
        return { 'x', 'y', 'radius' }
    elseif target._inputKind == 'Input' then
        return { 'sensitivity', 'speed', 'verticalSpeed' }
    end
    if target._body then
        local keys = {
            'type',
            'density',
            'friction',
            'restitution',
            'linearDamping',
            'angularDamping',
            'gravityScale',
            'autoSleep',
            'isTrigger',
            'canCollide',
            'canQuery',
            'collisionGroup',
        }
        for i = #keys, 1, -1 do
            if not Schema.visible(target, keys[i]) then
                table.remove(keys, i)
            end
        end
        return keys
    end
    if not target._class then
        return fallback
    end
    local keys, seen = {}, {}

    local function add(name)
        for _, key in ipairs(groups[name] or {}) do
            if not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end

    local function walk(class)
        if class.base then
            walk(class.base)
        end
        add(class.name)
        local own = {}
        for key in pairs(rawget(class, 'propertySchema') or {}) do
            own[#own + 1] = key
        end
        table.sort(own)
        for _, key in ipairs(own) do
            if not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
    walk(target._class)
    if target.modifier then
        keys = { 'name', 'enabled', 'layerGroup' }
        seen = { name = true, enabled = true, layerGroup = true }
        add(target.className)
    end
    if target:isA('BillboardUI') or target:isA('Decal3D') then
        for i = #keys, 1, -1 do
            if keys[i] == 'scale' then
                table.remove(keys, i)
            end
        end
    end
    if target:isA('Body3D') then
        for i = #keys, 1, -1 do
            if keys[i] == 'size' or keys[i] == 'scale' then
                table.remove(keys, i)
            end
        end
    end
    if target:isA('SurfaceUI') then
        local excluded = {
            offset = true,
            offsetWorldSpace = true,
            extentsOffset = true,
            extentsOffsetWorldSpace = true,
            screenPosition = true,
        }
        for i = #keys, 1, -1 do
            if excluded[keys[i]] then
                table.remove(keys, i)
            end
        end
    end
    for i = #keys, 1, -1 do
        if not Schema.visible(target, keys[i]) then
            table.remove(keys, i)
        end
    end
    return keys
end

-- Strict component check: a class-based node only accepts the properties its own class chain
-- declares. Special inspector targets (settings, bodies, inputs, modifiers) list their own keys.
function Schema.hasProperty(target, key)
    if
        not target._class
        or target._settingsKind
        or target._body
        or target._inputKind
        or target.emitters
        or target.modifier
    then
        return true
    end
    for _, name in ipairs(Schema.keys(target, {})) do
        if name == key then
            return true
        end
    end
    return false
end

function Schema.options(target, key)
    if key == 'shaderLayer' then
        local world = target._world or target._sceneWorld
        return world.shaderLayers.names
    end
    if key == 'layerGroup' or key == 'shadowGroup' then
        local world = target._world or target._sceneWorld
        return world and world.layerGroups.names
    end
    if key == 'collisionGroup' then
        local body = target.body or target._body
        local world = target._world or target._sceneWorld
        local physics = body and body.physics or world and world.physics
        return physics and physics.collisionGroups.names
    end
    if key == 'poseMode' then
        return { 'Render', 'Solver', 'Both' }
    end
    if key == 'followMode' then
        return { 'Free', 'FirstPerson', 'ThirdPerson' }
    end
    local options = Schema.descriptor(target, key).options
    if type(options) == 'function' then
        -- Dynamic lists (the bones of a model) may be empty: no list means a free text field.
        options = options(target)
        return options and #options > 0 and options or nil
    end
    if options then
        return options
    end
    if key == 'target' then
        if target:isA('UIStroke') then
            return { 'Border', 'Text' }
        end
        if target:isA('Ramp') then
            return { 'Background', 'Text' }
        end
    end
    if key == 'mode' then
        return target.isA and target:isA('Decal3D') and { 'Decal', 'Texture', 'Tiles', 'Atlas' }
            or { 'Exponential', 'Linear' }
    end
    if target._body and key == 'type' then
        return { 'Dynamic', 'Static', 'Kinematic' }
    end
    return enum[key]
end

function Schema.colorMaximum(target, key)
    if not (key:find('Color') or key == 'color' or key == 'ambient') then
        return
    end
    if target._colorMaximum then
        return target._colorMaximum
    end
    return target.isA
            and (target:isA('UINode') or target:isA('Mesh3D') or target:isA('Decal3D'))
            and 1
        or key:find('Color') and 1
        or 255
end

function Schema.reason(target, key)
    if Schema.descriptor(target, key).readOnly then
        return 'Reported by the runtime.'
    end
    if target.isA and target:isA('SurfaceUI') and key == 'sizeMode' then
        return 'SurfaceUI uses local surface units.'
    end
    if key == 'layoutStatus' then
        return 'Reported by responsive layout; authored Size is preserved.'
    end
    if key == 'parent' then
        return 'Use the hierarchy API to reparent nodes.'
    end
    if key == 'length' and target.automaticLength then
        return 'Computed from visible content; disable automaticLength for manual editing.'
    end
    if key == 'supportStatus' then
        return 'Reported by the spatial support validator.'
    end
    if key == 'status' or key == 'effectType' or key == 'actualMSAA' then
        return 'Reported by the runtime.'
    end
    if target.body and (key == 'size' or key == 'scale') then
        return 'Rebuild the rigid body to change collider dimensions.'
    end
    if
        target.isA
        and target:isA('World3D')
        and ({ position = true, rotation = true, scale = true })[key]
    then
        return 'World3D defines the fixed physics coordinate system.'
    end
end
-- Generic descriptors: a conditional property is hidden, never erased.
local descriptions = require('./schemaDescriptors')

function Schema.descriptor(target, key)
    if target._settingsKind == 'Shadows' then
        if key == 'filterSamples' then
            return {
                visibleWhen = { key = 'mode', equals = 'Standard' },
                hint = 'Standard PCF taps; Realistic uses fixed 9 blocker + 9 filter taps.',
            }
        end
        if key == 'mode' then
            return { options = { 'Standard', 'Realistic' } }
        end
        if key == 'lightSize' then
            return {
                min = 0,
                max = 0.25,
                hint = 'Approximate relative emitter size for contact-hardening shadows.',
                visibleWhen = { key = 'mode', equals = 'Realistic' },
            }
        end
        if key == 'softnessLimit' then
            return { min = 1, max = 16, hint = 'Maximum PCF filter radius in atlas pixels.' }
        end
        if key == 'blockerSearchRadius' then
            return {
                min = 1,
                max = 12,
                hint = 'Blocker-search radius in atlas pixels; 9 fixed taps.',
                visibleWhen = { key = 'mode', equals = 'Realistic' },
            }
        end
    end
    if target._settingsKind == 'Sky' then
        if key == 'texture' then
            return {
                hint = 'Project-relative sky image path or registered image name. Cross requires '
                    .. 'a 4:3 image.',
            }
        end
        if key == 'pixelate' then
            return { hint = 'Nearest sampling for this sky only; false uses linear smoothing.' }
        end
        if key == 'layout' then
            return { options = { 'Cross', 'Panorama' } }
        end
        if key == 'yaw' then
            return { hint = 'Sky rotation around the world Y axis, in degrees.' }
        end
    end
    local class = target._class
    while class do
        local descriptor = (rawget(class, 'propertySchema') or {})[key]
            or (descriptions[class.name] or {})[key]
        if descriptor then
            return descriptor
        end
        class = class.base
    end
    return {}
end

function Schema.visible(target, key)
    if target.isA then
        if
            target:isA('Environment')
            and target._dimension == 2
            and ({ systemLayers = true, toneMapping = true, exposure = true })[key]
        then
            return false
        end
        if
            target:isA('World3D')
            and ({ position = true, rotation = true, scale = true, size = true })[key]
        then
            return false
        end
        if target:isA('Collider2D') and ({ visible = true, transparency = true })[key] then
            return false
        end
    end
    local rule = Schema.descriptor(target, key).visibleWhen
    if key:match('^follow') and key ~= 'followMode' or key == 'pitchMin' or key == 'pitchMax' then
        if target.followMode == 'Free' then
            return false
        end
    end
    local bodyType = target._body and target._body.type or target.bodyType
    if
        bodyType
        and ({
            mass = true,
            density = true,
            gravityScale = true,
            linearDamping = true,
            angularDamping = true,
            autoSleep = true,
        })[key]
    then
        return bodyType == 'Dynamic'
    end
    if not rule then
        return true
    end
    if type(rule) == 'function' then
        return rule(target)
    end

    local function matches(r)
        if r.present then
            return target[r.key] ~= nil
        end
        if r.oneOf then
            for _, v in ipairs(r.oneOf) do
                if target[r.key] == v then
                    return true
                end
            end
            return false
        end
        return target[r.key] == r.equals
    end
    if rule.key then
        return matches(rule)
    end
    for _, r in ipairs(rule) do
        if not matches(r) then
            return false
        end
    end
    return true
end

function Schema.signature(target)
    return table.concat(Schema.keys(target, {}) or {}, '|')
end
local hints = require('./schemaHints')

function Schema.hint(target, key)
    if target.isA and target:isA('ScrollFrame') and key == 'canvasSize' then
        return 'UDim2 canvas dimensions relative to the frame plus logical pixels. '
            .. 'AutomaticCanvasSize can extend the authored minimum.'
    end
    if target._settingsKind == 'PhysicsDebug' and key == 'wireframe' then
        return 'Draw physics shapes as wire geometry. Does not change the main material renderer.'
    end
    if target._inputKind == 'Joystick' then
        return 'Safe-area logical pixels; authored values persist across resizing and are '
            .. 'clamped to the viewport.'
    end
    if key == 'sensitivity' then
        return 'Degrees per logical pixel for Free cameras. Follow cameras use followSensitivity.'
    end
    return Schema.descriptor(target, key).hint or hints[key]
end

return Schema
