local Objects = require('../../core.objects')
local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
-- Install one cohesive responsibility on the public class.
local Schema = require('./schema')
local limits = require('./propertyPolicy').limits
local PropertyWrite = {}

function PropertyWrite.install(Properties)
    -- Attribute rows: parse a typed value, or the "name = value" text of the add row.
    local function parseAttribute(text)
        text = text:match('^%s*(.-)%s*$')
        if text == 'true' or text == 'false' then
            return text == 'true'
        end
        local number = tonumber(text)
        if number then
            return number
        end
        local list = {}
        for part in text:gmatch('[^,]+') do
            local n = tonumber(part)
            if not n then
                list = nil
                break
            end
            list[#list + 1] = n
        end
        if list and #list >= 2 and #list <= 4 then
            return list
        end
        return (text:gsub('^"(.*)"$', '%1'))
    end

    local function setAttribute(target, field, text, component)
        if target.destroyed then
            return false, 'This node was removed'
        end
        if field.attributeNew then
            text = tostring(text or '')
            local name, kind = text:match('^%s*([^=:]-)%s*:%s*(%a+)%s*$')
            if name and name ~= '' and kind == 'node' then
                target:setAttributeReference(name, nil)
                return true
            end
            local key, rest = text:match('^%s*([^=]-)%s*=(.*)$')
            if not key or key == '' then
                return false, 'Write name = value, name: node, or name = (nothing) to remove'
            end
            if rest:match('^%s*$') then
                target:setAttribute(key, nil)
            else
                target:setAttribute(key, parseAttribute(rest))
            end
            return true
        end
        if field.kind == 'node' then
            if text ~= nil then
                local world = target._world or target._sceneWorld
                if not (type(text) == 'table' and text._node and not text.destroyed) then
                    return false, 'Expected a live node'
                end
                if world and (text._world or text._sceneWorld) ~= world then
                    return false, 'The node belongs to another world'
                end
            end
            target:setAttributeReference(field.key, text)
            return true
        end
        if field.readOnly then
            return false, field.reason or 'Property is read-only'
        end
        if field.kind == 'vector' then
            local current = target:getAttribute(field.key)
            local number = tonumber(text)
            if not component or type(current) ~= 'table' or not number then
                return false, 'Enter a finite number'
            end
            local copy = { unpack(current) }
            copy[component] = number
            target:setAttribute(field.key, copy)
        elseif field.kind == 'number' then
            local number = tonumber(text)
            if not number or number ~= number or math.abs(number) == math.huge then
                return false, 'Enter a finite number'
            end
            target:setAttribute(field.key, number)
        elseif field.kind == 'boolean' then
            target:setAttribute(field.key, text == true)
        else
            target:setAttribute(field.key, tostring(text))
        end
        return true
    end

    function Properties.set(scene, target, field, text, component)
        if field.attribute then
            return setAttribute(target, field, text, component)
        end
        if text == '<embedded image>' and Objects.isObject(target[field.key]) then
            return true
        end
        if field.kind == 'node' then
            local ok, err = pcall(function()
                local references = require('source.engine.editor.inspectors.nodeReferences')
                local expected = references.expected(target, field.key)
                if expected then
                    assert(
                        references.accepts(target, field.key, text),
                        field.key == 'geometrySource'
                                and 'Choose a live Node3D in this world or an existing OBJ / GLB / glTF path'
                            or 'Expected a live ' .. expected .. ' in this world'
                    )
                    if field.key == 'currentCamera' and target:isA('World2D') then
                        target:setCurrentCamera(text)
                    else
                        target[field.key] = text
                    end
                elseif field.key == 'currentCamera' then
                    target:setCurrentCamera(text)
                elseif field.key == 'positionSource' then
                    assert(
                        text == nil
                            or text:isA('Node3D')
                                and not text.destroyed
                                and (text._world or text._sceneWorld) == target._sceneWorld,
                        'Source must be a same-World3D live Node3D'
                    )
                    target.positionSource = text
                elseif target:isA('Ramp') then
                    target.adornee = text
                else
                    target:setAdornee(text)
                end
            end)
            return ok, ok and nil or tostring(err)
        end
        if field.container then
            target = field.container
        end
        if field.readOnly or field.key == 'parent' then
            return false, field.reason or 'Property is read-only'
        end
        if
            target.isA
            and target:isA('World3D')
            and (
                field.key == 'position'
                or field.key == 'rotation'
                or field.key == 'size'
                or field.key == 'scale'
            )
        then
            return false, 'World3D defines the fixed physics coordinate system'
        end
        if target.destroyed then
            return false, 'This node was removed'
        end
        if not Schema.hasProperty(target, field.key) then
            return false, (target.className or 'This node') .. ' has no property ' .. field.key
        end
        local key, value = field.storageKey or field.key, text
        if field.kind == 'number' or field.kind == 'vector' then
            value = tonumber(text)
            if not value or value ~= value or math.abs(value) == math.huge then
                return false, 'Enter a finite number'
            end
            local descriptor = Schema.descriptor(target, field.key)
            if
                descriptor.integer and value ~= math.floor(value)
                or descriptor.min and value < descriptor.min
                or descriptor.max and value > descriptor.max
            then
                return false, 'Value is outside the property range'
            end
            -- A descriptor with its own bounds replaces the shared per-name limit (a Glow
            -- `strength` is not a 0..1 opacity).
            local bound = not (descriptor.min or descriptor.max) and limits[field.key] or nil
            if
                bound
                and (
                    (bound[1] and value < bound[1])
                    or (bound[2] and value > bound[2])
                    or (bound[3] and value ~= math.floor(value))
                )
            then
                return false, 'Value is outside the allowed range'
            end
            if key == 'scale' and value <= 0.000001 then
                return false, 'Scale must exceed 0.000001'
            end
            if key == 'filterSamples' and value ~= 1 and value ~= 4 and value ~= 9 then
                return false, 'Use 1, 4 or 9'
            end
            if key == 'color' or key == 'ambient' then
                local maximum = field.colorMaximum
                    or (
                        target.isA
                            and (target:isA('Mesh3D') or target:isA('UINode') or target:isA(
                                'Decal3D'
                            ))
                            and 1
                        or 255
                    )
                if value < 0 or value > maximum then
                    return false, 'Color component out of range'
                end
            end
        elseif field.kind == 'boolean' then
            value = text == true
        end
        if
            key == 'pitchMin' and value > target.pitchMax
            or key == 'pitchMax' and value < target.pitchMin
        then
            return false, 'Pitch minimum must not exceed maximum'
        end
        if field.options then
            local found = false
            for _, option in ipairs(field.options) do
                if option == value then
                    found = true
                end
            end
            if not found then
                return false, 'Choose an available option'
            end
        end
        if target.isA and target:isA('Sound') then
            if
                key == 'minDistance' and value >= target.maxDistance
                or key == 'maxDistance' and value <= target.minDistance
            then
                return false, 'Sound requires minDistance < maxDistance'
            end
            if
                key == 'rolloff'
                and value ~= 'Linear'
                and value ~= 'LinearSquare'
                and value ~= 'Inverse'
            then
                return false, 'Use Linear, LinearSquare or Inverse'
            end
            if
                (key == 'resource' or key == 'stream' or key == 'spatial')
                and target._voice
                and not target._voice.released
            then
                return false, 'Stop Sound before changing its resource, stream or spatial mode'
            end
        end
        if
            (key == 'relativeTo' or key == 'sizeRelativeTo' or key == 'positionRelativeTo')
            and value ~= 'XY'
            and value ~= 'XX'
            and value ~= 'YY'
        then
            return false, 'Use XY, XX or YY'
        end
        if
            key == 'face'
            and not ({
                Front = true,
                Back = true,
                Left = true,
                Right = true,
                Top = true,
                Bottom = true,
            })[value]
        then
            return false, 'Use a local face name'
        end
        if
            key == 'mode'
            and target.isA
            and target:isA('Decal3D')
            and value ~= 'Decal'
            and value ~= 'Texture'
            and value ~= 'Tiles'
        then
            return false, 'Use Decal, Texture or Tiles'
        end
        if target.body and (key == 'size' or key == 'scale') then
            return false, 'Collider3D size requires rebuilding the rigid body'
        end
        if key == 'resolution' and value > katsa.graphics.getSystemLimits().texturesize then
            return false, 'Resolution exceeds GPU limits'
        end
        if key == 'direction' and component then
            local n = 0
            for i = 1, 3 do
                n = n + (i == component and value or target.direction[i]) ^ 2
            end
            if n < 1e-12 then
                return false, 'Direction must be nonzero'
            end
        end
        if target._settingsKind == 'Sky' and key == 'texture' then
            local ok, image =
                pcall(scene.resources.imageVariant, scene.resources, value, target.pixelate)
            if not ok then
                return false, tostring(image)
            end
            if
                target.layout == 'Cross'
                and not scene.resources:isMissingImage(value)
                and image:getWidth() * 3 ~= image:getHeight() * 4
            then
                return false, 'Cross sky must have 4:3 aspect ratio'
            end
        end
        if
            (
                key == 'image'
                or key == 'texture'
                    and target.isA
                    and (target:isA('ParticleEmitter3D') or target:isA('ParticleEmitter2D'))
            ) and field.kind == 'string'
        then
            local ok, err = pcall(scene.resources.image, scene.resources, value)
            if not ok then
                return false, tostring(err)
            end
        end
        if
            target.isA
            and target:isA('Label')
            and (key == 'text' and target.richText or key == 'richText' and value == true)
        then
            local ok, err = pcall(
                require('source.engine.ui.drawing.richText').parse,
                key == 'text' and value or target.text or '',
                true
            )
            if not ok then
                return false, tostring(err)
            end
        end
        if key == 'name' then
            if value == '' then
                return false, 'Name cannot be empty'
            end
            if target._world and target.isA and target:isA('Mesh3D') then
                local index = target._world.byName
                if index[value] and index[value] ~= target then
                    return false, 'Object name already exists'
                end
                local old = target.name
                index[old], index[value] = nil, target
                for _, board in ipairs(target._world.billboards) do
                    if board.adornee == old then
                        board.adornee = value
                    end
                end
            end
        end
        if
            component
            and (key == 'size' or key == 'position')
            and field.value
            and #field.value == 4
        then
            local copy = { unpack(target[key] or field.value) }
            copy[component] = value
            if key == 'size' and target.isA then
                local pw, ph, positive
                if target:isA('UINode') then
                    local parent = target.parent
                    pw = parent._width or target.ui.width
                    ph = parent._height or target.ui.height
                elseif target:isA('SurfaceUI') or target:isA('Decal3D') then
                    pw, ph = require('source.engine.world.surfaces.faces').referenceSize(target)
                    positive = true
                elseif target:isA('BillboardUI') then
                    if target.sizeMode == 'World3D' then
                        pw, ph = target:extentDimensions()
                    else
                        pw, ph = scene.camera.width, scene.camera.height
                    end
                end
                if pw then
                    local w, h = require('source.engine.ui.layout.metrics').resolve(
                        copy,
                        pw,
                        ph,
                        target.sizeRelativeTo or target.relativeTo
                    )
                    if w < 0 or h < 0 or positive and (w == 0 or h == 0) then
                        return false, 'Size resolves to invalid dimensions'
                    end
                end
            end
        end
        if
            (key == 'thickness' or key == 'radius' and target.isA and target:isA('UICorner'))
            and value < 0
        then
            return false, 'Scale/Offset must be nonnegative'
        end
        if key == 'supportSize' and value <= 0 then
            return false, 'Support dimensions must be positive'
        end
        if target._body then
            if target._body.object.destroyed then
                return false, 'Body3D owner was removed'
            end
            local ok, err = pcall(target._body.set, target._body, { [key] = value })
            return ok, ok and nil or tostring(err)
        end
        if target._inputKind == 'Joystick' then
            if key == 'radius' and value < 8 then
                return false, 'Joystick radius must be at least 8 pixels'
            end
            target.custom = true
        end
        local particlePrevious = target.isA
            and (target:isA('ParticleEmitter3D') or target:isA('ParticleEmitter2D'))
            and (component and target[key][component] or target[key])
        if component then
            if not target[key] then
                target[key] = { unpack(field.value) }
            end
            target[key][component] = value
        else
            target[key] = value
        end
        if target.isA and (target:isA('ParticleEmitter3D') or target:isA('ParticleEmitter2D')) then
            local system = target._particleSystem or target._world.particles
            local ok, err = pcall(system.validate, system, target)
            if not ok then
                if component then
                    target[key][component] = particlePrevious
                else
                    target[key] = particlePrevious
                end
                return false, tostring(err)
            end
        end
        if target.body and (key == 'position' or key == 'rotation') then
            target.body:teleportLocal(target.position, target.rotation)
        end
        if target.ui and target.ui.invalidate then
            target.ui:invalidate()
        end
        if target.isA and target:isA('BillboardUI') then
            target.dirty = true
        end
        if target.type == 'PointLight3D' or target.type == 'SpotLight3D' then
            target.forceUpdate = true
        end
        if scene.renderer then
            scene.renderer.lights.nextSelection = 0
        end
        -- The shared cache detects pose/property changes without invalidating unrelated sources.
        if target.emit then
            target:emit('propertyChanged', key, value, component)
        end
        return true
    end
end

return PropertyWrite
