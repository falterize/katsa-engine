local ipairs = require('source.engine.math.array').ipairs
local Hierarchy = require('source.engine.nodes.core.hierarchy')

local function process(record, dt, tree)
    local node = record.node
    if not node._started then
        node._started = true
        if node.start then
            node:start()
        end
        if not node.destroyed then
            node:emit('started', node)
        end
    end
    if record.enabled and node.enabled ~= false and not node.destroyed and node._tree == tree then
        if record.engineUpdate then
            record.engineUpdate(node, dt)
        end
        record.update(node, dt)
    end
end
local NodeTree = {}
NodeTree.__index = NodeTree

function NodeTree.new(root)
    local self = setmetatable({ root = root, records = {}, byNode = {} }, NodeTree)
    Hierarchy.bind(root, self, root._world)
    return self
end

function NodeTree:setProcess(node, enabled)
    assert(not self.released, 'NodeTree has been released')
    local record = self.byNode[node]
    if not enabled then
        if record then
            record.enabled = false
        end
        return
    end
    assert(
        not node.destroyed
            and not node._destroying
            and type(node._class.scriptUpdate or node.update) == 'function',
        'Processing requires a live node with update(dt)'
    )
    assert(node._tree == self, 'A processed node must belong to this NodeTree')
    assert(not node._startFailed, 'Start failed; fix and recreate the script node')
    if not record then
        record = { node = node }
        self.records[#self.records + 1], self.byNode[node] = record, record
        node._processTree = self
        node:onDestroy(function()
            record.enabled = false
            self.byNode[node], node._processTree = nil, nil
        end)
    end
    local owner = node
    while owner and not owner:isA('World2D') and not owner:isA('World3D') do
        owner = owner.parent
    end
    record.plane = owner and owner:isA('World2D') and owner or nil
    if record.plane then
        self.has2DProcesses = true
    end
    record.update, record.enabled = node._class.scriptUpdate or node.update, true
    record.engineUpdate = node._class.scriptUpdate
            and node:isA('Body3D')
            and require('source.engine.nodes').getClass('Body3D').update
        or nil
end

function NodeTree:update(dt)
    if self.released or dt <= 0 and not self.has2DProcesses then
        return
    end
    assert(not self.updating, 'NodeTree:update is not reentrant')
    self.updating = true
    local firstError
    local count = #self.records
    for i = 1, count do
        local record = self.records[i]
        local recordDt = dt
        if record and record.plane then
            recordDt = record.plane._simulationDelta
            if recordDt == nil then
                recordDt = require('source.engine.world.clock').delta(record.plane, dt)
            end
        end
        if
            record
            and record.enabled
            and recordDt > 0
            and not record.node.destroyed
            and record.node._tree == self
        then
            local node = record.node
            local starting = not node._started
            local ok, message = pcall(process, record, recordDt, self)
            if not ok then
                local world = node._world or node._sceneWorld
                local journal = world and world.resources.store.journal
                if journal then
                    local info = debug.getinfo(record.update, 'S')
                    journal:record('Node update', message, node, info and info.short_src)
                end
                if starting then
                    node._startFailed, record.enabled = true, false
                end
                firstError = firstError
                    or (
                        'Node '
                        .. tostring(node.name)
                        .. ' ('
                        .. node.className
                        .. ') update: '
                        .. tostring(message)
                    )
            end
        end
    end
    self.updating = false
    local write = 1
    for _, record in ipairs(self.records) do
        if not record.node.destroyed then
            self.records[write] = record
            write = write + 1
        end
    end
    for i = #self.records, write, -1 do
        self.records[i] = nil
    end
    if firstError then
        error(firstError, 0)
    end
end

function NodeTree:release()
    self.released = true
    for _, record in ipairs(self.records) do
        record.enabled = false
        if record.node._processTree == self then
            record.node._processTree = nil
        end
    end
    Hierarchy.bind(self.root, nil, self.root._sceneWorld)
    self.records, self.byNode = {}, {}
end

return NodeTree
