local Clone = require('source.engine.nodes.core.clone')

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

-- Rewrites one string that names a resource of the packed scene. `context.aliases` collects the
-- manifest entries the rewritten names stand for; the world that builds the template registers them.
local function resource(value, context)
    local resources = context.resources
    local entry = resources.manifest[value]
    if entry then
        local name = context.id .. ':' .. value
        local path = type(entry) == 'string' and entry or entry.path
        context.aliases[name] = type(entry) == 'string' and { path = resources:canonical(value) }
            or setmetatable({ path = resources:canonical(path) }, { __index = entry })
        return name
    end
    if value:sub(1, 8) == 'scene://' then
        return resources:canonical(value)
    end
    return value
end

-- A deep copy of a property value for the template.
local function convert(value, context)
    local kind = type(value)
    if kind == 'string' then
        return resource(value, context)
    elseif isNode(value) then
        local id = context.ids[value]
        -- A reference to something outside the packed content has no meaning in another world.
        return id and setmetatable({ id = id }, Ref) or nil
    elseif kind == 'table' and not getmetatable(value) then
        local result = {}
        for key, item in pairs(value) do
            result[key] = convert(item, context)
        end
        return result
    end
    return value
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
function Describe.children(container, baseline, resources, id)
    local context = { ids = {}, count = 0, aliases = {}, resources = resources, id = id }
    local function kind(node)
        if baseline[node] or node.destroyed then
            return 'skip'
        end
        return node._importerOwned and 'imported' or nil
    end
    local ids = {}
    walk(container, kind, function(node)
        context.count = context.count + 1
        ids[node], context.ids[node] = context.count, context.count
        return ids
    end, ids)
    local nodes = {}
    walk(container, kind, function(node, into)
        local entry = describeNode(node, context, ids)
        into[#into + 1] = entry
        return entry.children
    end, nodes)
    return { nodes = nodes, aliases = context.aliases }
end

return Describe
