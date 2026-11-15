local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
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

-- A path is child names separated by '/', like `game.Workspace.Map.House` in Roblox:
-- `scene.root:find('World3D/Map/House')`. A name may contain '/' itself: the path is matched
-- against the real children, so a node named "Test/" with a child "test2" is 'Test//test2' (the
-- slash of the name, then the separator). Empty steps are ignored.
-- Matches without allocating: it runs on every `scene.root:find('World3D/World2D')`.
local function resolve(node, rest, start)
    while rest:byte(start) == 47 do -- skip empty steps
        start = start + 1
    end
    if start > #rest then
        return node
    end
    for _, child in ipairs(node.children) do
        local name = child.name
        if type(name) == 'string' and name ~= '' and rest:find(name, start, true) == start then
            local after = start + #name
            if after > #rest then
                return child
            end
            if rest:byte(after) == 47 then
                local found = resolve(child, rest, after + 1)
                if found then
                    return found
                end
            end
        end
    end
end

-- `find(name)` / `find(path)`: direct children only. With `recursive` the first step is searched
-- in the whole subtree (depth first) and the rest follows child by child.
function Hierarchy.find(self, name, recursive)
    if type(name) ~= 'string' or not name:find('/', 1, true) then
        for _, child in ipairs(self.children) do
            if child.name == name then
                return child
            end
            if recursive then
                local found = child:find(name, true)
                if found then
                    return found
                end
            end
        end
        return nil
    end
    if not recursive then
        local found = resolve(self, name, 1)
        return found ~= self and found or nil
    end
    local function search(node)
        local found = resolve(node, name, 1)
        if found and found ~= node then
            return found
        end
        for _, child in ipairs(node.children) do
            found = search(child)
            if found then
                return found
            end
        end
    end
    return search(self)
end

-- The nearest ancestor with this name, or matching a filter table like findAll's
-- (`{ className = 'World3D' }`, `{ tag = 'Level' }`, `{ name = 'Map' }`).
function Hierarchy.findAncestor(self, filter)
    local ancestor = self.parent
    while ancestor do
        if type(filter) == 'string' then
            if ancestor.name == filter then
                return ancestor
            end
        elseif
            (not filter.name or ancestor.name == filter.name)
            and (not filter.className or ancestor:isA(filter.className))
            and (not filter.tag or ancestor:hasTag(filter.tag))
        then
            return ancestor
        end
        ancestor = ancestor.parent
    end
end

function Hierarchy.isDescendantOf(self, other)
    local ancestor = self.parent
    while ancestor do
        if ancestor == other then
            return true
        end
        ancestor = ancestor.parent
    end
    return false
end

-- The path from the top node (or from `relativeTo`, which must be an ancestor) to this node:
-- `node:getFullName(root)` can be given back to `root:find`.
function Hierarchy.getFullName(self, relativeTo)
    local names = {}
    local node = self
    while node and node ~= relativeTo do
        names[#names + 1] = tostring(node.name or node.className or '?')
        node = node.parent
    end
    assert(
        relativeTo == nil or node == relativeTo,
        'getFullName: relativeTo must be an ancestor of the node'
    )
    local reversed = {}
    for i = #names, 1, -1 do
        reversed[#reversed + 1] = names[i]
    end
    return table.concat(reversed, '/')
end

-- Calls `callback(node)` when `find(path)` has an answer: at once when the node exists, otherwise
-- as soon as a descendant is added that completes the path. Returns a handle: `handle.done`,
-- `handle:cancel()`. The wait ends with this node.
function Hierarchy.waitFor(self, path, callback)
    assert(type(callback) == 'function', 'waitFor expects a path and a callback')
    local handle = { done = false }
    local connection
    function handle.cancel()
        handle.done = true
        if connection then
            connection:disconnect()
        end
    end
    local found = self:find(path)
    if found then
        handle.done = true
        callback(found)
        return handle
    end
    connection = self:connect('descendantAdded', function()
        local node = not handle.done and self:find(path)
        if node then
            handle.cancel()
            callback(node)
        end
    end)
    self:trackConnection(connection)
    return handle
end

-- Tells every ancestor that listens that a node joined below it (waitFor); a plain tree walk
-- that stops costing anything once no ancestor holds a signal table.
function Hierarchy.announce(node, parent)
    local ancestor = parent
    while ancestor do
        if ancestor._signals and ancestor:hasConnections('descendantAdded') then
            ancestor:emit('descendantAdded', node)
        end
        ancestor = ancestor.parent
    end
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
