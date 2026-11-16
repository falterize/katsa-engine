local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local ModelNodes = require('./modelNodes')

-- Level of detail from node names inside a model file (.glb, .gltf, .obj, .blend):
--   <name>          the most detailed level
--   <name>-lod1     a coarser level, <name>-lod2 coarser still ... (`-lod0` also names level 0)
-- The nodes of one <name> become the children (levels) of a LODGroup named <name>LOD, put where the
-- most detailed node was. Skinned levels that share a skeleton keep playing the same animation.
-- Levels must have the same parent. `settings.lod` holds the LODGroup properties (`mode`,
-- `distances`, `screenSizes`, `bias`, `hysteresis`, `radius`); `lod = false` turns grouping off.
local AutoLod = {}

local GROUP_KEYS = { 'mode', 'distances', 'screenSizes', 'bias', 'hysteresis', 'radius' }

-- Returns the base name and the level number for a level node name, or nil.
function AutoLod.parse(name)
    if type(name) ~= 'string' then
        return nil
    end
    local clean = ModelNodes.stripCopy(name)
    local base, level = clean:match('^(.-)%-[Ll][Oo][Dd](%d+)$')
    if base and base ~= '' then
        return base, tonumber(level)
    end
    return nil
end

-- Collects { [base] = { [level] = instance } } in the order the bases first appear.
local function collect(list)
    local groups, order = {}, {}
    local function add(base, level, instance)
        local group = groups[base]
        if not group then
            group = {}
            groups[base], order[#order + 1] = group, base
        end
        group[level] = group[level] or instance
    end
    for _, entry in ipairs(list) do
        if entry.instance and ModelNodes.hasMesh(entry.instance) then
            local base, level = AutoLod.parse(entry.name)
            if base then
                add(base, level, entry.instance)
            else
                add(ModelNodes.stripCopy(entry.name), 0, entry.instance)
            end
        end
    end
    return groups, order
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
        local parent = levels[1].instance.parent
        local usable = #levels > 1
        for _, item in ipairs(levels) do
            usable = usable and item.instance ~= model.root and item.instance.parent == parent
        end
        if usable then
            local properties = { name = base .. 'LOD' }
            for _, key in ipairs(GROUP_KEYS) do
                properties[key] = options[key]
            end
            local group = world:create('LODGroup', properties, parent)
            for _, item in ipairs(levels) do
                item.instance.parent = group
            end
            group:update(0) -- only the most detailed level shows until a camera chooses
            created[#created + 1] = group
        end
    end
    return created
end

return AutoLod
