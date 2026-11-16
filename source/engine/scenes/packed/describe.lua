local Clone = require('source.engine.nodes.core.clone')
local Resource = require('./resource')

-- Turns the content a scene built into plain data (a template) that can be rebuilt in any world.
-- Nothing here keeps a node: references between nodes become `Ref` markers, resource names that
-- only the packed scene knows (`scene://` paths, manifest aliases) become names the importing
-- world can resolve, and imported models are recorded as "import this file again".
local Describe = {}

-- Marks a reference to another node of the same template (by id) inside copied values.
local Ref = {}
Describe.Ref = Ref

local function isNode(value)
    return type(value) == 'table' and rawget(value, '_node') == true
end

-- A deep copy of a property value for the template: resource names are rewritten, references to
-- nodes of the template become Refs (a reference to anything else has no meaning in another world).
local function convert(value, context)
    if isNode(value) then
        local id = context.ids[value]
        return id and setmetatable({ id = id }, Ref) or nil
    elseif type(value) == 'table' and not getmetatable(value) then
        local result = {}
        for key, item in pairs(value) do
            result[key] = convert(item, context)
        end
        return result
    end
    return Resource.deep(value, context)
end

local function describeAttributes(node, context)
    local list = {}
    for _, name in ipairs(node:getAttributeNames()) do
        local value = node:getAttribute(name)
        if node:isAttributeReference(name) then
            value = value and context.ids[value] and setmetatable({ id = context.ids[value] }, Ref)
        else
            value = convert(value, context)
        end
        if value ~= nil then
            list[#list + 1] = { name = name, value = value }
        end
    end
    return list
end

local function describeNode(node, context, ids)
    local properties = Clone.collect(node)
    for key, value in pairs(properties) do
        properties[key] = convert(value, context)
    end
    local entry = {
        id = ids[node],
        className = node.className,
        properties = properties,
        attributes = describeAttributes(node, context),
        tags = node:getTags(),
        viewportAuthored = node._viewportAuthored,
        children = {},
    }
    local source = node._modelSource
    if source then
        entry.model = {
            path = source.path,
            settings = convert(source.settings, context),
        }
    end
    return entry
end

-- Visits the nodes to pack. `kind(node)` is 'skip' (leave out with its subtree), 'imported' (a
-- node of an imported model: left out, but scene nodes below it are still packed, attached to the
-- model root) or nil. `visit(node, into)` receives the nodes to pack and returns the list their
-- own children go to.
local function walk(node, kind, visit, into)
    for _, child in ipairs(node.children) do
        local what = kind(child)
        if what == 'imported' then
            walk(child, kind, visit, into)
        elseif not what then
            walk(child, kind, visit, visit(child, into))
        end
    end
end

-- container: the node whose children are packed. `baseline`: nodes that exist without the scene
-- (what the host created) and are never packed. `resources` and `id` belong to the packed scene.
-- `huds`: containers of the scene's own overlay (World2D content); what the scene added there is
-- packed apart, as `hud`, and is shown on the overlay of the world that receives a copy.
function Describe.children(container, baseline, resources, id, huds)
    local context = { ids = {}, count = 0, aliases = {}, resources = resources, id = id }
    local function kind(node)
        if baseline[node] or node.destroyed then
            return 'skip'
        end
        return node._importerOwned and 'imported' or nil
    end
    local ids = {}
    local function number(node)
        context.count = context.count + 1
        ids[node], context.ids[node] = context.count, context.count
        return ids
    end
    local nodes, hud = {}, {}
    local function describe(node, into)
        local entry = describeNode(node, context, ids)
        into[#into + 1] = entry
        return entry.children
    end
    -- Ids first, so a reference may point at a node that comes later.
    walk(container, kind, number, ids)
    for _, hudContainer in ipairs(huds or {}) do
        walk(hudContainer, kind, number, ids)
    end
    walk(container, kind, describe, nodes)
    for _, hudContainer in ipairs(huds or {}) do
        walk(hudContainer, kind, describe, hud)
    end
    return { nodes = nodes, hud = hud, aliases = context.aliases }
end

return Describe
