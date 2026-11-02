local Objects = require('../core.objects')
local Store = require('./store')
local Files = require('./files')
local Settings = require('./settings')
local Paths = require('./paths')
local Formats = require('./formats')

local Data = {}
Data.__index = Data

local function optionsFor(parent, options)
    local result = {}
    for _, key in ipairs({ 'filesystem', 'maxBytes', 'maxFileBytes' }) do
        result[key] = parent and parent[key]
    end
    for key, value in pairs(options or {}) do
        result[key] = value
    end
    return result
end

local function storeFor(self, options)
    if not options then
        return self.store
    end
    local merged = {}
    for key, value in pairs(self._options) do
        merged[key] = value
    end
    for key, value in pairs(options) do
        merged[key] = value
    end
    return Store.new(self.name, merged)
end

local function operate(self, operation, filename, value, options)
    local ok, result, metadata = pcall(function()
        local format, exact = Formats.resolve(filename, options)
        local backend = format == 'json' and storeFor(self, options) or self.files
        if operation == 'write' then
            assert(
                format == 'json' or Objects.isObject(value) or type(value) ~= 'table',
                'Use a .json filename for tables, or specify format = json on write and read'
            )
            return backend:write(filename, value, exact)
        end
        return backend[operation](backend, filename, exact)
    end)
    if not ok then
        return nil, tostring(result)
    end
    return result, metadata
end

function Data.new(namespace, options)
    local root = namespace == nil
    namespace = Paths.namespace(namespace or 'shared')
    options = optionsFor(nil, options)
    return setmetatable({
        name = namespace,
        _rootScope = root,
        _options = options,
        store = Store.new(namespace, options),
        files = Files.new(namespace, options),
    }, Data)
end

function Data:scope(namespace, options)
    namespace = Paths.namespace(namespace)
    local path = self._rootScope and namespace or self.name .. '/' .. namespace
    return Data.new(path, optionsFor(self._options, options))
end

function Data:read(filename, options)
    return operate(self, 'read', filename, nil, options)
end

function Data:write(filename, value, options)
    return operate(self, 'write', filename, value, options)
end

function Data:delete(filename, options)
    return operate(self, 'remove', filename, nil, options)
end

function Data:exists(filename)
    local ok, format, exact = pcall(Formats.resolve, filename)
    if not ok then
        return false
    end
    if format == 'json' and not exact then
        local a, b = self.store:paths(filename)
        return self.store.fs.getInfo(a, 'file') ~= nil or self.store.fs.getInfo(b, 'file') ~= nil
    end
    return self.files:exists(filename)
end

function Data:load(slot)
    return self.store:read(slot)
end

function Data:save(slot, value)
    return self.store:write(slot, value)
end

function Data:remove(slot)
    return self.store:remove(slot)
end

function Data:settings(file, options)
    if type(file) == 'table' or file == nil then
        assert(options == nil, 'Use settings(options) or settings(filename, options)')
        options = file
        file = nil
    end
    options = optionsFor(self._options, options)
    if file ~= nil then
        options.file = file
    end
    return Settings.new(self.name, options)
end

function Data:directory()
    return self.store.fs.getSaveDirectory()
end

function Data:scopeDirectory()
    return self:directory() .. '/' .. self.store.root
end

function Data:createDirectory(path)
    return self.files:createDirectory(path)
end

function Data:listDirectories(path)
    return self.files:listDirectories(path)
end

-- Compatibility entry points preserve raw bytes regardless of the extension.
function Data:readFile(path)
    return self.files:read(path)
end

function Data:writeFile(path, bytes)
    return self.files:write(path, bytes)
end

function Data:fileExists(path)
    return self.files:exists(path)
end

function Data:listFiles(directory, recursive)
    return self.files:list(directory, recursive)
end

function Data:removeFile(path)
    return self.files:remove(path)
end

function Data:openFile(path, mode)
    return self.files:open(path, mode)
end

function Data:filePath(path)
    return self.files:readPath(path) or self.files:path(path)
end

return Data
