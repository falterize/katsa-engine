local Store = require('source.engine.persistence.store')

local Settings = {}
Settings.__index = Settings

function Settings.new(namespace, options)
    options = options or {}
    local store = Store.new(namespace, options)
    local file = options.file or 'settings'
    local values, metadata = store:read(file)
    if not values then
        return nil, metadata
    end
    return setmetatable(
        { store = store, file = file, values = values, metadata = metadata, dirty = false },
        Settings
    )
end

function Settings:get(key)
    return self.values[key]
end

function Settings:set(key, value)
    assert(type(key) == 'string', 'Setting names must be strings')
    if self.values[key] ~= value then
        self.values[key] = value
        self.dirty = true
    end
end

function Settings:save()
    if not self.dirty and not self.metadata.migrated then
        return true, self.metadata
    end
    local ok, metadata = self.store:write(self.file, self.values)
    if ok then
        self.dirty, self.metadata = false, metadata
    end
    return ok, metadata
end

return Settings
