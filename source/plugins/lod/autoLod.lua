local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local ModelNodes = require('source.engine.import.modelNodes')

-- Level of detail from node names inside a model file (.glb, .gltf, .obj, .blend):
--   <name>-lod0     the most detailed level (a plain <name> is level 0 too, but not both)
--   <name>-lod1     a coarser level, <name>-lod2 coarser still ...
-- The nodes of one <name> become the children (levels) of a LODGroup named <name>LOD, put where the
-- most detailed node was. A `-col` / `-colonly` suffix may come before or after the LOD one (see
-- autoCollision); `-colonly` meshes are collision proxies and never become levels. Levels may sit
-- under different parents: they move into the group and keep their place in the world. Skinned
-- levels that share a skeleton keep playing the same animation.
-- `settings.lod` holds the LODGroup properties for every group of the model (`mode`, `distances`,
-- `screenSizes`, `bias`, `fadeTime`, `animationRates` ...); `settings.lod.groups = { Tree = {...} }`
-- overrides them for one group by its <name>; `lod = false` turns grouping off.
local AutoLod = {}

-- Returns the base name and the level number for a level node name, or nil.
function AutoLod.parse(name)
    local parsed = ModelNodes.parse(name)
    if parsed and parsed.level then
        return parsed.base, parsed.level
    end
    return nil
end

-- Collects { [base] = { [level] = instance } } in the order the bases first appear. A node without
-- a LOD suffix is level 0 of its own full name (so `Tree-col` stays a separate mesh from `Tree`).
local function collect(list)
    local groups, order, names = {}, {}, {}
    local function add(base, level, entry)
        local group = groups[base]
        if not group then
            group, names[base] = {}, {}
            groups[base], order[#order + 1] = group, base
        end
        local clean = ModelNodes.stripCopy(entry.name)
        local known = names[base][level]
        if known and known ~= clean then
            error(
                'Model nodes "'
                    .. known
                    .. '" and "'
                    .. clean
                    .. '" are both level '
                    .. level
                    .. ' of "'
                    .. base
                    .. '"; rename one',
                0
            )
        end
        names[base][level] = clean
        group[level] = group[level] or entry.instance
    end
    for _, entry in ipairs(list) do
        if entry.instance and ModelNodes.hasMesh(entry.instance) then
            local parsed = ModelNodes.parse(entry.name)
            if not (parsed and parsed.collision == 'only') then
                if parsed and parsed.level then
                    add(parsed.base, parsed.level, entry)
                else
                    add(ModelNodes.stripCopy(entry.name), 0, entry)
                end
            end
        end
    end
    return groups, order
end

local function isAncestor(node, other)
    local parent = other.parent
    while parent do
        if parent == node then
            return true
        end
        parent = parent.parent
    end
    return false
end

-- True when the levels can move into one group: more than one, none is the model root and none
-- contains another.
local function usable(model, levels)
    if #levels < 2 then
        return false
    end
    for _, item in ipairs(levels) do
        if item.instance == model.root then
            return false
        end
        for _, other in ipairs(levels) do
            if item ~= other and isAncestor(item.instance, other.instance) then
                return false
            end
        end
    end
    return true
end

-- The LODGroup properties of one group: the shared ones, then the overrides for its name.
local function propertiesFor(options, base)
    local properties = {}
    for key, value in pairs(options) do
        if key ~= 'groups' then
            properties[key] = value
        end
    end
    for key, value in pairs(options.groups and options.groups[base] or {}) do
        properties[key] = value
    end
    properties.name = base .. 'LOD'
    return properties
end

-- Creates the LODGroups; returns the list of them.
function AutoLod.apply(world, model, objects, settings)
    settings = settings or {}
    if settings.lod == false then
        return {}
    end
    local options = settings.lod or {}
    local groups, order = collect(ModelNodes.candidates(model, objects))
    local created = {}
    for _, base in ipairs(order) do
        local levels = {}
        for level, instance in pairs(groups[base]) do
            levels[#levels + 1] = { level = level, instance = instance }
        end
        table.sort(levels, function(a, b)
            return a.level < b.level
        end)
        if usable(model, levels) then
            local group =
                world:create('LODGroup', propertiesFor(options, base), levels[1].instance.parent)
            for _, item in ipairs(levels) do
                item.instance:setParent(group, { keepWorldTransform = true })
            end
            group:update(0) -- only the most detailed level shows until a camera chooses
            created[#created + 1] = group
        end
    end
    return created
end

return AutoLod
