local Clone = require('source.engine.nodes.core.clone')
local Node = require('source.engine.nodes')
local Ref = require('./describe').Ref
local Resource = require('./resource')

-- Builds a template (describe.lua) into a world: the reverse of packing.
local Build = {}

local function isRef(value)
    return getmetatable(value) == Ref
end

-- A copy of `value` with every Ref replaced by its node; `hasRefs` tells whether any were found.
local function resolve(value, nodes)
    if isRef(value) then
        return nodes[value.id], true
    elseif type(value) == 'table' and not getmetatable(value) then
        local result, found = {}, false
        for key, item in pairs(value) do
            local resolved, has = resolve(item, nodes)
            result[key], found = resolved, found or has
        end
        return result, found
    end
    return value, false
end

-- Properties without node references (those are assigned once every node exists).
local function plain(properties)
    local result, deferred = {}, {}
    for key, value in pairs(properties) do
        local _, has = resolve(value, {})
        if has then
            deferred[key] = value
        else
            result[key] = value
        end
    end
    return result, deferred
end

-- A world keeps its meshes in one registry by name, so a mesh is created under a free name and
-- then shown under its own: the paths inside every copy stay the same.
local function registryName(world, className, name)
    if name and Node.getClass(className, world)._types.Mesh3D then
        return Clone.uniqueName(world, name)
    end
    return name
end

-- The meshes of an imported model are named after its root while it is imported; the root is
-- named apart from the other instances for that moment only (the node keeps its own name).
local function importName(world, name)
    local used = world._packedModelNames or {}
    world._packedModelNames = used
    used[name] = (used[name] or 0) + 1
    return used[name] == 1 and name or (name .. '_' .. used[name])
end

-- Some classes create required children themselves (the UI of a BillboardUI, an Environment inside
-- a World); the copy of such a child is not created again but takes the packed properties.
-- Creates a node whose name may repeat (see registryName); returns it.
function Build.create(world, className, properties, parent)
    local name = properties.name
    properties.name = registryName(world, className, name)
    local node = world:create(className, properties, parent)
    node.name = name or node.name
    return node
end

local function adopt(entry, parent, automatic)
    local existing = entry.properties.name and parent:find(entry.properties.name)
    if existing and automatic[existing] and existing.className == entry.className then
        return existing
    end
end

local function createNode(world, entry, parent, automatic)
    local properties, deferred = plain(entry.properties)
    local name = properties.name
    local node = adopt(entry, parent, automatic)
    if node then
        for key, value in pairs(properties) do
            node[key] = value
        end
        return node, deferred
    end
    if entry.model then
        local Models = require('source.engine.import.models')
        local settings = {}
        for key, value in pairs(entry.model.settings) do
            settings[key] = value
        end
        settings.parent = parent
        settings.name = importName(world, name)
        local _, root = Models.instantiate(world, Models.load(entry.model.path, world.resources), settings)
        node = root
        for key, value in pairs(properties) do
            node[key] = value
        end
        node.name = name or node.name
    else
        node = Build.create(world, entry.className, properties, parent)
    end
    -- What the class made by itself (required children), remembered for `adopt`.
    for _, child in ipairs(node.children) do
        automatic[child] = true
    end
    return node, deferred
end

local function buildList(world, list, parent, nodes, later, automatic)
    for _, entry in ipairs(list) do
        local node, deferred = createNode(world, entry, parent, automatic)
        nodes[entry.id] = node
        later[#later + 1] = { node = node, entry = entry, deferred = deferred }
        buildList(world, entry.children, node, nodes, later, automatic)
    end
end

-- Creates the template's nodes under `parent` and its World2D nodes (also under `parent`, each
-- with its own HUD content and children); returns every node by id and the World2D nodes.
function Build.nodes(world, template, parent)
    Resource.register(world, template.aliases)
    local nodes, later, automatic = {}, {}, {}
    buildList(world, template.nodes, parent, nodes, later, automatic)
    local worlds = {}
    for _, entry in ipairs(template.world2d) do
        local node, deferred = createNode(world, entry, parent, automatic)
        nodes[entry.id] = node
        later[#later + 1] = { node = node, entry = entry, deferred = deferred }
        buildList(world, entry.content, node.content, nodes, later, automatic)
        buildList(world, entry.children, node, nodes, later, automatic)
        worlds[#worlds + 1] = { node = node, main = entry.main }
    end
    for _, item in ipairs(later) do
        local node, entry = item.node, item.entry
        node._viewportAuthored = entry.viewportAuthored
        for key, value in pairs(item.deferred) do
            node[key] = (resolve(value, nodes))
        end
        for _, attribute in ipairs(entry.attributes) do
            if isRef(attribute.value) then
                node:setAttributeReference(attribute.name, nodes[attribute.value.id])
            else
                node:setAttribute(attribute.name, (resolve(attribute.value, nodes)))
            end
        end
        for _, tag in ipairs(entry.tags) do
            node:addTag(tag)
        end
    end
    return nodes, worlds
end

return Build
