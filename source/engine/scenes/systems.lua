local Systems = {}
Systems.__index = Systems

function Systems.new(scene)
    return setmetatable({ scene = scene, ordered = {}, named = {}, updating = false }, Systems)
end

function Systems:add(name, system, enabled)
    assert(not self.released and not self.updating, 'Register systems outside update callbacks')
    assert(type(name) == 'string' and not self.named[name], 'Duplicate system: ' .. tostring(name))
    assert(type(system) == 'table', 'A system must be a module instance')
    local entry = { name = name, system = system, enabled = enabled ~= false }
    self.named[name] = entry
    self.ordered[#self.ordered + 1] = entry
    if entry.enabled and system.start then
        system:start(self.scene)
        entry.started = true
    end
    return system
end

function Systems:setEnabled(name, enabled)
    local entry = assert(self.named[name], 'Unknown system: ' .. tostring(name))
    assert(type(enabled) == 'boolean', 'System enabled must be a boolean')
    entry.enabled = enabled
    if enabled and not entry.started and entry.system.start then
        entry.system:start(self.scene)
        entry.started = true
    end
end

function Systems:isEnabled(name)
    return assert(self.named[name], 'Unknown system: ' .. tostring(name)).enabled
end

function Systems:update(dt)
    self.updating = true
    for i = 1, #self.ordered do
        local entry = self.ordered[i]
        if entry.enabled and entry.system.update then
            entry.system:update(dt)
        end
    end
    self.updating = false
end

function Systems:update3D(dt)
    self.updating = true
    for i = 1, #self.ordered do
        local entry = self.ordered[i]
        if entry.enabled and entry.system.update3D then
            entry.system:update3D(dt)
        end
    end
    self.updating = false
end

function Systems:update2D(dt, realDt)
    self.updating = true
    for i = 1, #self.ordered do
        local entry = self.ordered[i]
        if entry.enabled and entry.system.update2D then
            entry.system:update2D(dt, realDt)
        end
    end
    self.updating = false
end

function Systems:release()
    if self.released then
        return
    end
    self.released = true
    local failure
    for i = #self.ordered, 1, -1 do
        local system = self.ordered[i].system
        if system.release then
            local ok, message = pcall(system.release, system)
            failure = failure or not ok and message
        end
    end
    self.ordered, self.named = {}, {}
    if failure then
        error(failure, 0)
    end
end

return Systems
