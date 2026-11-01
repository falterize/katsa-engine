local Array = require('source.engine.math.array')
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Queries return snapshots: callers can safely modify the live tree afterward.
local Hierarchy = {}

function Hierarchy.getChildren(self)
    local result = {}
    for i, child in ipairs(self.children) do
        result[i] = child
    end
    return result
end

function Hierarchy.getDescendants(self)
    local result = {}

    local function visit(node)
        for _, child in ipairs(node.children) do
            result[#result + 1] = child
            visit(child)
        end
    end
    visit(self)
    return result
end

function Hierarchy.findAll(self, filter, recursive)
    assert(Array.is(filter), 'findAll expects a name/className/tag filter')
    local result = {}

    local function visit(node)
        for _, child in ipairs(node.children) do
            if
                (not filter.name or child.name == filter.name)
                and (not filter.className or child:isA(filter.className))
                and (not filter.tag or child:hasTag(filter.tag))
            then
                result[#result + 1] = child
            end
            if recursive then
                visit(child)
            end
        end
    end
    visit(self)
    return result
end

function Hierarchy.findByType(self, className, recursive)
    return self:findAll({ className = className }, recursive)[1]
end

function Hierarchy.findByTag(self, tag, recursive)
    return self:findAll({ tag = tag }, recursive)[1]
end

function Hierarchy.addTag(self, tag)
    assert(not self.destroyed and not self._destroying, 'Tags require a live node')
    assert(type(tag) == 'string' and tag ~= '', 'Tag must be a nonempty string')
    self._tags = self._tags or {}
    self._tags[tag] = true
    return self
end

function Hierarchy.removeTag(self, tag)
    if self._tags then
        self._tags[tag] = nil
    end
    return self
end

function Hierarchy.hasTag(self, tag)
    return self._tags and self._tags[tag] == true or false
end

function Hierarchy.getTags(self)
    local result = {}
    for tag in pairs(self._tags or {}) do
        result[#result + 1] = tag
    end
    table.sort(result)
    return result
end

function Hierarchy.bind(node, tree, sceneWorld)
    if node._worldBoundary and node._nodeTree and tree ~= node._nodeTree then
        return
    end
    node._tree = tree
    -- Scene identity survives detach. Recreate scene-owned nodes to migrate.
    node._sceneWorld = node._sceneWorld or sceneWorld
    local record = tree and tree.byNode and tree.byNode[node]
    if record and record.enabled then
        -- Reparenting can change the clock owner without changing the NodeTree.
        tree:setProcess(node, true)
    end
    for _, child in ipairs(node.children) do
        Hierarchy.bind(child, tree, sceneWorld)
    end
end

return Hierarchy
