-- What the Create tab offers: every item knows how to build itself through the undoable
-- `ops:create`. Positions come from the editor's placement point (in front of the camera).
local Clone = require('source.engine.nodes.core.clone')
local Shapes = require('./shapes')

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
            local world = content.scene.world
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
            local properties = { name = Clone.uniqueName(content.scene.world, label), position = { position[1], position[2] + 2, position[3] } }
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
            local ops, undo, world = content.ops, content.undo, content.scene.world
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

function Catalog.items()
    return {
        primitive('Cube', 'cube', { 2, 2, 2 }),
        primitive('Sphere', 'sphere', { 2, 2, 2 }),
        primitive('Plane', 'plane', { 4, 0.01, 4 }),
        primitive('Capsule', 'capsule', { 1, 2, 1 }),
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
                    name = Clone.uniqueName(content.scene.world, 'SpawnPoint'),
                    kind = 'capsule',
                    position = lifted(position, 1.8),
                    size = { 0.6, 1.8, 0.6 },
                    color = { 0.2, 0.85, 0.35, 0.8 },
                }, nil, { SpawnPoint = true })
            end,
        },
        volume('Trigger', true),
        volume('Collider', false),
        {
            group = 'Objects',
            label = 'Billboard',
            make = function(content, position)
                return content.ops:create('BillboardUI', {
                    name = Clone.uniqueName(content.scene.world, 'Billboard'),
                    position = { position[1], position[2] + 2, position[3] },
                })
            end,
        },
    }
end

return Catalog
