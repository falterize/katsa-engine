-- What the Create tab offers: every item knows how to build itself through the undoable
-- `ops:create`. Positions come from the editor's placement point (in front of the camera).
local Affine = require('source.engine.math.affine')
local Clone = require('source.engine.nodes.core.clone')
local Math = require('source.engine.math.math3d')
local Shapes = require('./shapes')
local UiText = require('../core.uiText')

local Catalog = {}

local GREY = { 0.75, 0.76, 0.8, 1 }

local function lifted(position, height)
    return { position[1], position[2] + height / 2, position[3] }
end

local function primitive(label, kind, size)
    return {
        group = 'Primitives',
        label = label,
        make = function(content, position)
            local world = content.world
            local properties = {
                name = Clone.uniqueName(world, label),
                position = lifted(position, size[2]),
                size = { size[1], size[2], size[3] },
                color = { GREY[1], GREY[2], GREY[3], 1 },
            }
            local attributes
            if kind == 'cylinder' or kind == 'cone' then
                properties.geometry = Shapes.geometry(world, kind)
                attributes = { EditorShape = kind }
            else
                properties.kind = kind
            end
            return content.ops:create('Mesh3D', properties, nil, attributes)
        end,
    }
end

local function plain(group, label, class, extra)
    return {
        group = group,
        label = label,
        make = function(content, position)
            local properties = { name = Clone.uniqueName(content.world, label), position = { position[1], position[2] + 2, position[3] } }
            for key, value in pairs(extra or {}) do
                properties[key] = value
            end
            return content.ops:create(class, properties)
        end,
    }
end

-- A Body3D with a Collider3D (and a see-through box so it can be seen and picked).
local function volume(label, trigger)
    return {
        group = 'Objects',
        label = label,
        make = function(content, position)
            local ops, undo, world = content.ops, content.undo, content.world
            local name = Clone.uniqueName(world, label)
            local color = trigger and { 0.2, 0.9, 0.45, 0.25 } or { 0.6, 0.6, 0.65, 0.35 }
            undo:begin('Create ' .. label)
            local body = ops:create('Body3D', {
                name = name,
                bodyType = 'Static',
                position = lifted(position, 3),
            })
            ops:create('Collider3D', { name = name .. 'Collider', shape = 'Box', size = { 3, 3, 3 }, isTrigger = trigger }, body)
            ops:create('Mesh3D', { name = name .. 'View', kind = 'cube', size = { 3, 3, 3 }, color = color }, body)
            undo:commit()
            content.selection:set({ body })
            return body
        end,
    }
end

-- The face of `host` that looks most toward the camera, so a new decal or board is seen at
-- once (the default Front face is the host's -Z side, often turned away from the editor view).
local FACES = { { 'Left', 'Right' }, { 'Bottom', 'Top' }, { 'Front', 'Back' } }

local function faceToward(host, camera)
    local ok, inverse = pcall(Affine.inverse, host:getWorldMatrix())
    if not ok or not camera then
        return 'Front'
    end
    local eye = camera.worldPosition or camera.position
    local x, y, z = Math.transform(inverse, eye[1], eye[2], eye[3])
    local local3, best, face = { x, y, z }, -1, 'Front'
    local size = host.size or { 1, 1, 1 }
    for axis = 1, 3 do
        local weight = math.abs(local3[axis]) / math.max(1e-6, size[axis])
        if weight > best then
            best, face = weight, FACES[axis][local3[axis] < 0 and 1 or 2]
        end
    end
    return face
end

-- A node that lives on a surface (Decal3D, SurfaceUI, SurfaceAppearance3D): it goes under the
-- selected mesh, or under a new cube when nothing suitable is selected. `child` is an optional
-- first child, so the node shows something at once.
local function surfaceNode(group, label, class, extra, child, needsHost, text)
    return {
        group = group,
        label = label,
        make = function(content, position)
            local ops, world = content.ops, content.world
            content.undo:begin('Create ' .. label)
            local host = content.selection:primary()
            if not (host and (host:isA('Mesh3D') or (not needsHost and host:isA('Node3D')))) then
                host = ops:create('Mesh3D', {
                    name = Clone.uniqueName(world, label .. ' host'),
                    kind = 'cube',
                    position = lifted(position, 2),
                    size = { 2, 2, 2 },
                    color = { GREY[1], GREY[2], GREY[3], 1 },
                })
            end
            local properties = { name = Clone.uniqueName(world, label) }
            for key, value in pairs(extra or {}) do
                properties[key] = value
            end
            if class == 'Decal3D' then
                properties.face = properties.face or faceToward(host, content.camera)
            end
            local node = ops:create(class, properties, host)
            if text then
                UiText.set(node, text)
            end
            content.undo:commit()
            content.selection:set({ node })
            return node
        end,
    }
end

function Catalog.items()
    return {
        primitive('Cube', 'cube', { 2, 2, 2 }),
        primitive('Sphere', 'sphere', { 2, 2, 2 }),
        primitive('Plane', 'plane', { 4, 0.01, 4 }),
        primitive('Capsule', 'capsule', { 1, 1, 1 }),
        primitive('Cylinder', 'cylinder', { 1.5, 2, 1.5 }),
        primitive('Cone', 'cone', { 1.5, 2, 1.5 }),
        plain('Lights', 'Point light', 'PointLight3D'),
        plain('Lights', 'Spot light', 'SpotLight3D', { rotation = { 60, 0, 0 } }),
        plain('Lights', 'Sun', 'DirectionalLight3D', { rotation = { 50, 35, 0 } }),
        plain('Objects', 'Empty', 'Node3D'),
        plain('Objects', 'Camera', 'Camera3D'),
        {
            group = 'Objects',
            label = 'Spawn point',
            make = function(content, position)
                return content.ops:create('Mesh3D', {
                    name = Clone.uniqueName(content.world, 'SpawnPoint'),
                    kind = 'capsule',
                    position = lifted(position, 1.8),
                    size = { 0.9, 0.9, 0.9 },
                    color = { 0.2, 0.85, 0.35, 0.8 },
                }, nil, { SpawnPoint = true })
            end,
        },
        volume('Trigger', true),
        volume('Collider', false),
        {
            group = 'Visual',
            label = 'Billboard (always faces camera)',
            make = function(content, position)
                content.undo:begin('Create Billboard')
                local node = content.ops:create('BillboardUI', {
                    name = Clone.uniqueName(content.world, 'Billboard'),
                    position = { position[1], position[2] + 2, position[3] },
                })
                UiText.set(node, 'Billboard')
                content.undo:commit()
                content.selection:set({ node })
                return node
            end,
        },
        surfaceNode('Visual', 'Surface UI', 'SurfaceUI', nil, nil, nil, 'Surface UI'),
        surfaceNode('Visual', 'Decal', 'Decal3D'),
        surfaceNode('Visual', 'Surface appearance', 'SurfaceAppearance3D', nil, nil, true),
        plain('Visual', 'Particles', 'ParticleEmitter3D'),
        plain('Visual', 'Attachment', 'Attachment3D'),
    }
end

return Catalog
