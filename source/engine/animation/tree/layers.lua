-- Layer attributes a graph node hands down to the clips beneath it. The tree turns them into
-- AnimationTrack settings, so the Animator does the mixing: `boost` raises the layer order (the
-- clips play over everything below), `filter` limits the bones, `additive` adds the clips on top.
local Layers = {}

-- A filter is a list of bone names (weight 1) or a map of bone name to weight.
local function normalize(filter)
    local map = {}
    for key, value in pairs(filter) do
        if type(key) == 'number' then
            map[value] = 1
        else
            map[key] = value
        end
    end
    return map
end

-- Everything under `node` goes through `options`: { boost = n, filter = {...}, additive = true,
-- reference = 'firstFrame' | 'rest', children = true }.
function Layers.apply(node, options)
    local leaves = {}
    node:collect(leaves)
    for _, leaf in ipairs(leaves) do
        if options.boost then
            leaf.orderBoost = (leaf.orderBoost or 0) + options.boost
        end
        if options.additive then
            leaf.additive = true
            leaf.additiveReference = options.reference or leaf.additiveReference
        end
        if options.filter then
            leaf.filters = leaf.filters or {}
            leaf.filters[#leaf.filters + 1] = {
                weights = normalize(options.filter),
                children = options.children == true,
            }
        end
    end
end

-- Bones below `name` in the skeleton (children are 0-based node indices).
local function descendants(model, name, map, weight)
    local byName = {}
    for index, bone in ipairs(model.nodes) do
        byName[bone.name or index] = bone
    end
    local function walk(bone)
        for _, childIndex in ipairs(bone.children or {}) do
            local child = model.nodes[childIndex + 1]
            if child and child.name and map[child.name] == nil then
                map[child.name] = weight
                walk(child)
            end
        end
    end
    if byName[name] then
        walk(byName[name])
    end
end

-- The bone mask of a leaf: its own `mask` multiplied by every filter above it.
function Layers.mask(leaf, model)
    local mask = leaf.definition.mask
    for _, filter in ipairs(leaf.filters or {}) do
        local weights = {}
        for name, weight in pairs(filter.weights) do
            weights[name] = weight
        end
        if filter.children and model and model.nodes then
            for name, weight in pairs(filter.weights) do
                descendants(model, name, weights, weight)
            end
        end
        if mask then
            local merged = {}
            for name, weight in pairs(weights) do
                if mask[name] then
                    merged[name] = weight * mask[name]
                end
            end
            mask = merged
        else
            mask = weights
        end
    end
    return mask
end

return Layers
