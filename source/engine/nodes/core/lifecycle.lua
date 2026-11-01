local ipairs = require('source.engine.math.array').ipairs
local Hierarchy = require('source.engine.nodes.core.hierarchy')
local Signals = require('source.engine.nodes.core.signals')

local Lifecycle = {}

function Lifecycle.onDestroy(self, callback)
    assert(
        not self.destroyed and not self._destroying and type(callback) == 'function',
        'onDestroy requires a live node and callback'
    )
    self._cleanup[#self._cleanup + 1] = callback
    return callback
end

function Lifecycle.trackConnection(self, connection)
    assert(
        connection and type(connection.disconnect) == 'function',
        'Expected a disconnectable connection'
    )
    self:onDestroy(function()
        connection:disconnect()
    end)
    return connection
end

function Lifecycle.own(self, resource)
    assert(
        resource and type(resource.release) == 'function',
        'Expected an exclusively owned releasable resource'
    )
    self:onDestroy(function()
        resource:release()
    end)
    return resource
end

function Lifecycle.destroy(self)
    if self.destroyed or self._destroying then
        return
    end
    self._destroying = true
    -- Unlink before callbacks: destroying an ancestor from a child's callback
    -- cannot encounter this already-closing child in its live child list.
    local parent = self.parent
    if parent then
        for i, child in ipairs(parent.children) do
            if child == self then
                table.remove(parent.children, i)
                break
            end
        end
    end
    rawset(self, '_parent', nil)
    if self._tree then
        Hierarchy.bind(self, nil, self._sceneWorld)
    end
    local children = self:getChildren()
    local firstError

    local function attempt(callback, ...)
        local ok, message = pcall(callback, ...)
        if not ok then
            firstError = firstError or message
        end
    end
    attempt(self.emit, self, 'destroying', self)
    for _, child in ipairs(children) do
        attempt(child.destroy, child)
    end
    self.destroyed = true
    Signals.clear(self)
    for i = #self._cleanup, 1, -1 do
        attempt(self._cleanup[i], self)
    end
    self._cleanup, self._tags = {}, nil
    self.onPress, self.onMove, self.onRelease, self.onChange = nil, nil, nil, nil
    if self.ui and self.ui.invalidate then
        attempt(self.ui.invalidate, self.ui)
    end
    if firstError then
        error(firstError, 0)
    end
end

return Lifecycle
