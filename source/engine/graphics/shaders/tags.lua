local pairs = require('../../math.array').pairs

-- Shader tags bind a shader node to objects through the ordinary tag system.
--
--   #shader-<group>    on a node: the group's shaders act on this node and its descendants
--   #noshader-<group>  on a node: the group's shaders skip this node and its descendants
--
-- How far a tag reaches is counted in tree levels, the tagged node being level 0. The include depth
-- is the node's `shaderDepth.<group>` attribute; -1 or nothing is unlimited; the
-- exclude depth is the node's `noShaderDepth.<group>` attribute, else unlimited. For an object the
-- nearest ancestor (the object itself counts) whose tag reaches it decides, and at one node an
-- exclusion beats an inclusion. A shader without a `#shader-` tag keeps its subtree scope; tagged
-- shaders sharing a group stack by the usual shader layer priority.
local Tags = {}

local INCLUDE, EXCLUDE = '#shader-', '#noshader-'
local INCLUDE_DEPTH, EXCLUDE_DEPTH = 'shaderDepth.', 'noShaderDepth.'

local function prefixed(tag, prefix)
    return type(tag) == 'string' and #tag > #prefix and tag:sub(1, #prefix) == prefix
end

-- Whether `tag` is an engine shader tag (`#shader-<group>` or `#noshader-<group>`).
function Tags.is(tag)
    return prefixed(tag, INCLUDE) or prefixed(tag, EXCLUDE)
end

-- Whether the node carries at least one `#shader-` tag.
function Tags.has(node)
    local tags = rawget(node, '_tags')
    if tags then
        for tag in pairs(tags) do
            if prefixed(tag, INCLUDE) then
                return true
            end
        end
    end
    return false
end

-- Whether the node carries any `#shader-` or `#noshader-` tag.
function Tags.any(node)
    local tags = rawget(node, '_tags')
    if tags then
        for tag in pairs(tags) do
            if Tags.is(tag) then
                return true
            end
        end
    end
    return false
end

local function depthOf(node, name)
    local attributes = rawget(node, '_attributes')
    local value = attributes and attributes[name]
    -- A missing or negative depth reaches the whole subtree.
    return type(value) == 'number' and value >= 0 and value or math.huge
end

-- Whether one group's tags on `node` reach an object `distance` levels below it. Returns true
-- (included), false (excluded) or nil (this node says nothing about the object).
local function decide(shader, node, group, distance)
    local tags = rawget(node, '_tags')
    if not tags then
        return nil
    end
    if tags[EXCLUDE .. group] and distance <= depthOf(node, EXCLUDE_DEPTH .. group) then
        return false
    end
    if tags[INCLUDE .. group] and distance <= depthOf(node, INCLUDE_DEPTH .. group) then
        return true
    end
    return nil
end

-- Whether the tagged `shader` acts on `object`: any of the shader's groups includes it.
function Tags.applies(shader, object)
    local own = rawget(shader, '_tags')
    if not own then
        return false
    end
    for tag in pairs(own) do
        if prefixed(tag, INCLUDE) then
            local group = tag:sub(#INCLUDE + 1)
            local node, distance = object, 0
            while node do
                local verdict = decide(shader, node, group, distance)
                if verdict ~= nil then
                    if verdict then
                        return true
                    end
                    break
                end
                node, distance = node.parent, distance + 1
            end
        end
    end
    return false
end

-- A tag or a depth attribute changed on `node`: the render resolves shader stacks again and the UI
-- repaints.
function Tags.changed(node, tag)
    if not Tags.is(tag) and not prefixed(tag, INCLUDE_DEPTH) and not prefixed(tag, EXCLUDE_DEPTH) then
        return
    end
    local world = rawget(node, '_sceneWorld') or rawget(node, '_world')
    if world and world.invalidateRender then
        world:invalidateRender()
    end
    if node.isA and node:isA('UINode') and node.ui then
        node.ui:invalidate()
    end
end

return Tags
