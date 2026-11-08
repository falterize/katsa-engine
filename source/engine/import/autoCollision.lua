-- Godot-style collision from node names inside a model file (.glb, .gltf, .obj, and .blend through
-- its glTF conversion):
--   <name>-col       the mesh keeps rendering and gets an exact (Trimesh) static collider
--   <name>-colonly   the mesh is hidden and acts as collision only
-- For `-colonly`, when another mesh node named <name> exists, the collider is attached to that node
-- (so it moves with it); otherwise it is an invisible collision object at its own place.
-- Blender's ".001" duplicate suffix is ignored. Needs World3D.physics; without it nothing is created.
local ipairs = require('../math.array').ipairs

local AutoCollision = {}

local SUFFIXES = { { '-colonly', 'only' }, { '-col', 'visible' } }

-- Returns the base name and the kind ('visible' | 'only') for a collision node name, or nil.
function AutoCollision.parse(name)
    if type(name) ~= 'string' then
        return nil
    end
    local clean = name:gsub('%.%d+$', '')
    local lower = clean:lower()
    for _, entry in ipairs(SUFFIXES) do
        local suffix = entry[1]
        if #lower > #suffix and lower:sub(-#suffix) == suffix then
            return clean:sub(1, #clean - #suffix), entry[2]
        end
    end
    return nil
end

local function stripCopy(name)
    return (name:gsub('%.%d+$', ''))
end

-- entries: list of { name = string, instance = node }
local function candidates(model, objects)
    local list = {}
    if model.nodes then
        for _, n in ipairs(model.nodes) do
            if n.instance and not n.isBone then
                list[#list + 1] = { name = n.name, instance = n.instance }
            end
        end
    else
        for i, part in ipairs(model.parts) do
            local object = objects[i]
            if object and part.name then
                list[#list + 1] = { name = part.name, instance = object }
            end
        end
    end
    return list
end

local function hasMesh(instance)
    if instance:isA('Mesh3D') then
        return true
    end
    for _, child in ipairs(instance.children or {}) do
        if child:isA('Mesh3D') then
            return true
        end
    end
    return false
end

-- Creates the bodies; returns the list of created Body3D nodes.
function AutoCollision.apply(world, model, objects, settings)
    settings = settings or {}
    if settings.autoCollision == false or not world.physics then
        return {}
    end
    local list = candidates(model, objects)
    local byName = {}
    for _, entry in ipairs(list) do
        entry.base, entry.kind = AutoCollision.parse(entry.name)
        entry.mesh = entry.instance and hasMesh(entry.instance)
        if not entry.kind and entry.mesh then
            byName[entry.name] = byName[entry.name] or entry
            byName[stripCopy(entry.name)] = byName[stripCopy(entry.name)] or entry
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
