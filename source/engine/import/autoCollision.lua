-- Godot-style collision from node names inside a model file (.glb, .gltf, .obj, and .blend through
-- its glTF conversion):
--   <name>-col       the mesh keeps rendering and gets an exact (Trimesh) static collider
--   <name>-colonly   the mesh is hidden and acts as collision only
-- For `-colonly`, when another mesh node named <name> exists, the collider is attached to that node
-- (so it moves with it); otherwise it is an invisible collision object at its own place.
-- Blender's ".001" duplicate suffix is ignored. Needs World3D.physics; without it nothing is created.
local ipairs = require('../math.array').ipairs
local ModelNodes = require('./modelNodes')

local AutoCollision = {}

local SUFFIXES = { { '-colonly', 'only' }, { '-col', 'visible' } }

-- Returns the base name and the kind ('visible' | 'only') for a collision node name, or nil.
function AutoCollision.parse(name)
    if type(name) ~= 'string' then
        return nil
    end
    local clean = ModelNodes.stripCopy(name)
    local lower = clean:lower()
    for _, entry in ipairs(SUFFIXES) do
        local suffix = entry[1]
        if #lower > #suffix and lower:sub(-#suffix) == suffix then
            return clean:sub(1, #clean - #suffix), entry[2]
        end
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
        entry.base, entry.kind = AutoCollision.parse(entry.name)
        entry.mesh = entry.instance and ModelNodes.hasMesh(entry.instance)
        if not entry.kind and entry.mesh then
            local clean = ModelNodes.stripCopy(entry.name)
            byName[entry.name] = byName[entry.name] or entry
            byName[clean] = byName[clean] or entry
        end
    end
    local bodies = {}
    for _, entry in ipairs(list) do
        if entry.kind and entry.mesh then
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
