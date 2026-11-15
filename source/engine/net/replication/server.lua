local Operations = require('./operations')
local Storage = require('./storage')
local Values = require('./values')

-- Server side of node replication. At every snapshot tick it compares the replicated nodes with
-- what it last sent and sends the differences. See replication/init.lua for the rules.
local ServerReplication = {}
ServerReplication.__index = ServerReplication

-- The replicable state of a node: its name, parent id, the properties it lists and its attributes.
local function readState(node, parentId)
    local props, attrs = {}, {}
    for _, key in ipairs(rawget(node, 'replicatedProperties') or {}) do
        props[key] = Values.plain(node[key])
    end
    for key, value in pairs(rawget(node, '_attributes') or {}) do
        attrs[key] = Values.plain(value)
    end
    return { name = node.name, parent = parentId, props = props, attrs = attrs }
end

-- endpoint: the net Server. options.roots: nodes to scan (default the world root and ReplicatedStorage).
function ServerReplication.new(endpoint, world, options)
    local self = setmetatable({
        endpoint = endpoint,
        world = world,
        roots = options and options.roots,
        records = {},
        byNode = setmetatable({}, { __mode = 'k' }),
        nextId = Storage.REPLICATED_ID + 1,
    }, ServerReplication)
    self.replicatedStorage, self.serverStorage = Storage.install(world, true)
    self.roots = self.roots or { world._node, self.replicatedStorage }
    self.replicatedStorage.replicatedContainer = true
    self.records[Storage.REPLICATED_ID] = { node = self.replicatedStorage }
    return self
end

function ServerReplication:record(node)
    local record = self.byNode[node]
    if record then
        return record
    end
    record = { id = self.nextId, node = node }
    self.nextId = self.nextId + 1
    self.records[record.id] = record
    self.byNode[node] = record
    return record
end

-- Appends the operation a replicated node needs, and returns its id for its children.
function ServerReplication:track(node, parentId, seen, ops)
    local record = self:record(node)
    local state = readState(node, parentId)
    seen[record.id] = true
    if not record.sent then
        ops[#ops + 1] = Operations.create(record.id, node.className, state)
    else
        ops[#ops + 1] = Operations.change(record.id, record.sent, state)
    end
    record.sent = state
    return record.id
end

function ServerReplication:visit(node, parentId, insideStorage, seen, ops)
    if node.destroyed or node == self.serverStorage then
        return
    end
    if node == self.replicatedStorage then
        parentId, insideStorage = Storage.REPLICATED_ID, true
    elseif insideStorage or rawget(node, 'replicated') == true then
        parentId = self:track(node, parentId, seen, ops)
    end
    for _, child in ipairs(node.children) do
        self:visit(child, parentId, insideStorage, seen, ops)
    end
end

-- Nodes that were replicated before and are gone (destroyed or no longer marked).
function ServerReplication:removals(seen, ops)
    local gone = {}
    for id in pairs(self.records) do
        if id ~= Storage.REPLICATED_ID and not seen[id] then
            gone[#gone + 1] = id
        end
    end
    table.sort(gone)
    for _, id in ipairs(gone) do
        self.byNode[self.records[id].node] = nil
        self.records[id] = nil
        ops[#ops + 1] = { op = Operations.REMOVE, id = id }
    end
end

-- Returns the operations since the last call, parents before children.
function ServerReplication:collect()
    local ops, seen = {}, {}
    for _, root in ipairs(self.roots) do
        self:visit(root, 0, false, seen, ops)
    end
    self:removals(seen, ops)
    return ops
end

-- At each snapshot tick: sends the differences to every ready player. Returns how many.
function ServerReplication:step()
    local ops = self:collect()
    if #ops > 0 then
        for _, player in pairs(self.endpoint.players) do
            if player.ready then
                Operations.send(player, ops)
            end
        end
    end
    return #ops
end

-- The whole replicated tree for a player who has just joined.
function ServerReplication:sendAll(player)
    local ids = {}
    for id, record in pairs(self.records) do
        if record.sent then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local ops = {}
    for _, id in ipairs(ids) do
        local record = self.records[id]
        ops[#ops + 1] = Operations.create(id, record.node.className, record.sent)
    end
    if #ops > 0 then
        Operations.send(player, ops)
    end
end

return ServerReplication
