-- Godot-style collision from node names inside a model file (.glb, .gltf, .obj, and .blend through
-- its glTF conversion):
--   <name>-col       the mesh keeps rendering and gets an exact (Trimesh) static collider
--   <name>-colonly   the mesh is hidden and acts as collision only
-- The suffix may sit before or after a LOD suffix (`Tree-lod0-col` = `Tree-col-lod0`). A visible
-- `-col` on a coarser level (`Tree-lod1-col`) is ignored with a warning, since only the most
-- detailed level has a collider; name a hidden `Tree-colonly` mesh for a simpler shape.
-- For `-colonly`, when another mesh node named <name> exists, the collider is attached to that node
-- (so it moves with it); otherwise it is an invisible collision object at its own place.
-- Blender's ".001" duplicate suffix is ignored. Needs World3D.physics; without it nothing is created.
local ipairs = require('../math.array').ipairs
local ModelNodes = require('./modelNodes')

local AutoCollision = {}

-- Returns the base name, the kind ('visible' | 'only') and the level (nil without a LOD suffix) for
-- a collision node name, or nil.
function AutoCollision.parse(name)
    local parsed = ModelNodes.parse(name)
    if parsed and parsed.collision then
        return parsed.base, parsed.collision, parsed.level
    end
    return nil
end

-- Creates the bodies; returns the list of created Body3D nodes.
function AutoCollision.apply(world, model, objects, settings)
    settings = settings or {}
    if settings.autoCollision == false or not world.physics then
        return {}
    end
    local list = ModelNodes.candidates(model, objects)
    local byName = {}
    for _, entry in ipairs(list) do
        entry.base, entry.kind, entry.level = AutoCollision.parse(entry.name)
        entry.mesh = entry.instance and ModelNodes.hasMesh(entry.instance)
        if not entry.kind and entry.mesh then
            local clean = ModelNodes.stripCopy(entry.name)
            byName[entry.name] = byName[entry.name] or entry
            byName[clean] = byName[clean] or entry
            local parsed = ModelNodes.parse(entry.name)
            if parsed and parsed.level == 0 then
                byName[parsed.base] = byName[parsed.base] or entry
            end
        end
    end
    local bodies = {}
    for _, entry in ipairs(list) do
        if entry.kind == 'visible' and (entry.level or 0) > 0 then
            ModelNodes.warn(
                world,
                'Collider of "' .. entry.name .. '" ignored: only the most detailed level has one'
            )
        elseif entry.kind and entry.mesh then
            local source = entry.instance
            local owner
            if entry.kind == 'only' then
                source.visible = false
                local target = byName[entry.base]
                -- With a visual twin the collider travels with it; alone it stays where it is.
                owner = target and target.instance or source.parent or model.root
            else
                owner = source
            end
            local body = world:create('Body3D', {
                name = entry.name .. 'Body',
                bodyType = 'Static',
                friction = settings.friction,
                restitution = settings.restitution,
                collisionGroup = settings.collisionGroup,
            }, owner)
            world:create('Collider3D', {
                shape = 'Geometry',
                geometrySource = source,
                collisionLevel = settings.collisionLevel or 'Trimesh',
            }, body)
            bodies[#bodies + 1] = body
        end
    end
    return bodies
end

return AutoCollision
