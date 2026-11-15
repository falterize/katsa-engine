local pairs = require('../../math.array').pairs

-- Shader tags bind a shader node to objects through the ordinary tag system: a Shader3D or
-- Shader2D tagged `#shader-<group>` acts only on nodes of its world kind that carry the same tag.
-- A shader without a `#shader-` tag keeps its subtree scope. Tagged shaders sharing a tag stack by
-- the usual shader layer priority; the layer interaction matrix applies to them like any other.
local Tags = {}

local PREFIX = '#shader-'

function Tags.is(tag)
    return type(tag) == 'string' and #tag > #PREFIX and tag:sub(1, #PREFIX) == PREFIX
end

-- Whether the node carries at least one `#shader-` tag.
function Tags.has(node)
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

-- Whether the shader and the target carry a common `#shader-` tag.
function Tags.shares(shader, target)
    local own, other = rawget(shader, '_tags'), rawget(target, '_tags')
    if own and other then
        for tag in pairs(own) do
            if other[tag] and Tags.is(tag) then
                return true
            end
        end
    end
    return false
end

-- A tag changed on `node`: the render resolves shader stacks again and the UI repaints.
function Tags.changed(node, tag)
    if not Tags.is(tag) then
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
