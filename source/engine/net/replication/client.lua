local Operations = require('./operations')
local Storage = require('./storage')

-- Client side of node replication: builds and updates the nodes the server describes. Nodes the
-- client makes itself are never touched.
local ClientReplication = {}
ClientReplication.__index = ClientReplication

-- endpoint: the net Client; it owns the `nodeCreated` signal.
function ClientReplication.new(endpoint, world)
    local self = setmetatable({ endpoint = endpoint, world = world, records = {} }, ClientReplication)
    self.replicatedStorage = Storage.install(world, false)
    self.records[Storage.REPLICATED_ID] = self.replicatedStorage
    return self
end

-- The node an id stands for: 0 is the world itself.
function ClientReplication:resolve(id)
    return id == 0 and self.world._node or self.records[id]
end

local function setAttributes(node, attrs, removed)
    for key, value in pairs(attrs or {}) do
        node:setAttribute(key, value)
    end
    for _, key in ipairs(removed or {}) do
        node:setAttribute(key, nil)
    end
end

-- A copy lists the properties the server sends, so the inspector can show them.
local function listProperties(node, props)
    local keys = {}
    for _, key in ipairs(rawget(node, 'replicatedProperties') or {}) do
        keys[key] = true
    end
    for key in pairs(props or {}) do
        keys[key] = true
    end
    local list = {}
    for key in pairs(keys) do
        list[#list + 1] = key
    end
    table.sort(list)
    node.replicatedProperties = #list > 0 and list or nil
end

function ClientReplication:create(op)
    local parent = self:resolve(op.parent)
    if not parent or parent.destroyed then
        return
    end
    local properties = { name = op.name }
    for key, value in pairs(op.props) do
        properties[key] = value
    end
    local ok, node = pcall(self.world.create, self.world, op.class, properties, parent)
    if not ok then
        katsa.log.warn('Replication could not create ' .. tostring(op.class) .. ': ' .. tostring(node))
        return
    end
    setAttributes(node, op.attrs)
    node.replica = true
    listProperties(node, op.props)
    -- The server's flag is not sent; a replica shows it so the Explorer reads like the server tree.
    node.replicated = true
    self.records[op.id] = node
    self.endpoint.nodeCreated:fire(node)
end

function ClientReplication:change(op)
    local node = self.records[op.id]
    if not node or node.destroyed then
        return
    end
    node.name = op.name or node.name
    local parent = op.parent and self:resolve(op.parent)
    if parent and parent ~= node.parent then
        node:setParent(parent)
    end
    for key, value in pairs(op.props or {}) do
        node[key] = value
    end
    if op.props then
        listProperties(node, op.props)
    end
    setAttributes(node, op.attrs, op.removedAttrs)
end

function ClientReplication:remove(op)
    local node = self.records[op.id]
    self.records[op.id] = nil
    if node and not node.destroyed then
        node:destroy()
    end
end

-- Applies a batch received from the server, in order.
function ClientReplication:apply(ops)
    for _, op in ipairs(ops) do
        if op.op == Operations.CREATE then
            self:create(op)
        elseif op.op == Operations.CHANGE then
            self:change(op)
        elseif op.op == Operations.REMOVE then
            self:remove(op)
        end
    end
end

return ClientReplication
