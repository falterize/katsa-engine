local Package = require('source.engine.scenes.package')
local Cleanup = require('source.engine.core.cleanup')

local Interface = {}
Interface.__index = function(self, key)
    local method = Interface[key]
    if method then
        return method
    end
    local state = rawget(self, 'state')
    return state and state[key]
end

local events = {
    'resize',
    'pointerpressed',
    'pointermoved',
    'pointerreleased',
    'pointercancelled',
    'wheelmoved',
    'keypressed',
    'keyreleased',
    'textinput',
    'pause',
    'resume',
    'exit',
}

function Interface.new(manager, source)
    local package = type(source) == 'table' and source or Package.open(source)
    return setmetatable(
        { manager = manager, data = manager.data, package = package, simulation = false },
        Interface
    )
end

function Interface:load()
    self.lifecycle = require('source.engine.scenes.layout').lifecycle(self.package)
    self.state = self.lifecycle.create(self, self.package)
    for _, name in ipairs(events) do
        local method = self.state[name]
        if method then
            self[name] = function(_, ...)
                return method(self.state, ...)
            end
        end
    end
end

function Interface:update(dt, realDt)
    local state = self.state
    self.lifecycle.update2D(state, dt, realDt)
    self.lifecycle.update(state, dt)
    self.lifecycle.update3D(state, dt)
end

function Interface:draw()
    local state = self.state
    if state.draw then
        state:draw()
    else
        state.ui:draw()
    end
end

function Interface:canReuseWindowFrame()
    local state = self.state
    return state.canReuseWindowFrame and state:canReuseWindowFrame() or false
end

function Interface:release()
    local state = self.state or self.package.instance
    Cleanup.run({
        function()
            if state then
                self.lifecycle.destroy(state)
            end
        end,
        function()
            self.package:release()
        end,
    })
end

return Interface
