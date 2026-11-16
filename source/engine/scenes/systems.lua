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

-- Registers every module in `<scene root>/systems` once, at creation: `settings` maps a system name to
-- { order, enabled } (default order 100, enabled), the rest is alphabetical. A system module exports
-- create(state, scene, context, settings) returning the system.
function Systems.discover(scene, context, state, settings)
    settings = settings or {}
    local entries = {}
    local folder = context.root .. '/systems'
    for _, filename in ipairs(katsa.filesystem.getDirectoryItems(folder)) do
        if
            filename:match('%.lua$')
            and katsa.filesystem.getInfo(folder .. '/' .. filename, 'file')
        then
            local name = assert(filename:match('^([%w_]+)%.lua$'), 'Invalid system module: ' .. filename)
            local own = settings[name] or { order = 100, enabled = true }
            entries[#entries + 1] = { name = name, settings = own, order = own.order or 100 }
        end
    end
    table.sort(entries, function(a, b)
        if a.order == b.order then
            return a.name < b.name
        end
        return a.order < b.order
    end)
    for _, entry in ipairs(entries) do
        local Module = context:require('systems.' .. entry.name)
        assert(
            type(Module.create) == 'function',
            'System must export create(state, scene, context)'
        )
        scene.systems:add(
            entry.name,
            Module.create(state, scene, context, entry.settings),
            entry.settings.enabled
        )
    end
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
