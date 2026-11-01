local Counter = {}
Counter.__index = Counter

function Counter.new(node)
    return setmetatable({ node = node }, Counter)
end

function Counter:start()
    self.started = true
end

function Counter:update(dt)
    self.node.ticks = self.node.ticks + dt
end

function Counter:release()
    self.released = true
end

return Counter
