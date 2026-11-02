local Json = require('vendor.json')
local Paths = require('./paths')
local FileIO = require('./fileIO')

local Store = {}
Store.__index = Store

local function copy(value)
    return Json.decode(Json.encode(value))
end

local function defaults(data, fallback)
    for key, value in pairs(fallback) do
        if data[key] == nil then
            data[key] = copy(value)
        elseif type(data[key]) == 'table' and type(value) == 'table' then
            defaults(data[key], value)
        end
    end
    return data
end

local function checksum(payload)
    return katsa.data.encode('string', 'hex', katsa.data.hash('sha256', payload))
end

function Store.new(namespace, options)
    options = options or {}
    local version = options.version or 1
    assert(type(version) == 'number' and version >= 1 and version % 1 == 0, 'Invalid save version')
    return setmetatable({
        root = 'saves/' .. Paths.namespace(namespace),
        version = version,
        defaults = copy(options.defaults or {}),
        migrations = options.migrations or {},
        fs = options.filesystem or katsa.filesystem,
        maxBytes = options.maxBytes or 8 * 1024 * 1024,
    }, Store)
end

function Store:paths(slot, exact)
    local name = Paths.relative(slot or 'progress')
    local stem = self.root .. '/' .. name
    if exact or name:match('[^/]+$'):find('.', 1, true) then
        return stem, stem .. '.bak', true
    end
    return stem .. '.a.json', stem .. '.b.json'
end

function Store:decode(path)
    local fs = self.fs
    local info = fs.getInfo(path)
    if not info then
        return nil, 'missing'
    end
    local ok, record = pcall(function()
        assert(info.type == 'file' and info.size <= self.maxBytes, 'Invalid save size')
        local envelope = Json.decode(assert(fs.read(path)))
        assert(envelope.format == 1, 'Unknown save envelope')
        assert(type(envelope.payload) == 'string', 'Missing save payload')
        assert(checksum(envelope.payload) == envelope.checksum, 'Save checksum mismatch')
        local data = Json.decode(envelope.payload)
        assert(type(data.data) == 'table', 'Save data must be a table')
        assert(
            type(data.version) == 'number' and data.version >= 1 and data.version % 1 == 0,
            'Invalid save schema'
        )
        assert(
            type(data.generation) == 'number' and data.generation >= 1 and data.generation % 1 == 0,
            'Invalid save generation'
        )
        data.path = path
        return data
    end)
    if ok then
        return record
    end
    return nil, tostring(record)
end

function Store:latest(slot, exact)
    local a, b = self:paths(slot, exact)
    local first, firstError = self:decode(a)
    local second, secondError = self:decode(b)
    local record = first
    if second and (not record or second.generation > record.generation) then
        record = second
    end
    local damaged = firstError ~= nil and firstError ~= 'missing'
        or secondError ~= nil and secondError ~= 'missing'
    return record, damaged, a, b
end

function Store:read(slot, exact)
    local ok, data, metadata = pcall(function()
        local record, damaged, _, backup = self:latest(slot, exact)
        if not record then
            assert(not damaged, 'Both save generations are unavailable or damaged')
            return copy(self.defaults), { status = 'new', version = self.version, generation = 0 }
        end
        assert(record.version <= self.version, 'Save was created by a newer game version')
        local originalVersion = record.version
        local _, _, named = self:paths(slot, exact)
        while record.version < self.version do
            local migrate = assert(self.migrations[record.version], 'Missing save migration')
            record.data = assert(migrate(record.data), 'Migration must return the new data')
            assert(type(record.data) == 'table', 'Migration data must be a table')
            record.version = record.version + 1
        end
        return defaults(record.data, self.defaults),
            {
                status = (damaged or named and record.path == backup) and 'recovered' or 'loaded',
                generation = record.generation,
                version = record.version,
                migrated = originalVersion ~= record.version,
            }
    end)
    if not ok then
        return nil, tostring(data)
    end
    return data, metadata
end

function Store:write(slot, data, exact)
    local ok, metadata = pcall(function()
        assert(type(data) == 'table', 'Save data must be a table')
        local record, damaged, a, b = self:latest(slot, exact)
        assert(
            record or not damaged,
            'Refusing to overwrite damaged saves; recover or delete first'
        )
        assert(not record or record.version <= self.version, 'Cannot overwrite a newer save schema')
        local generation = record and record.generation + 1 or 1
        local payload =
            Json.encode({ version = self.version, generation = generation, data = data })
        local bytes = Json.encode({ format = 1, checksum = checksum(payload), payload = payload })
        assert(#bytes <= self.maxBytes, 'Save exceeds the size limit')
        local _, _, named = self:paths(slot, exact)
        if named then
            FileIO.publish(self.fs, a, bytes, function(temporary)
                assert(self:decode(temporary), 'Save verification failed')
            end, record and record.path == b)
            return { generation = generation, version = self.version, path = a }
        end
        local target = record and record.path == a and b or a
        local temporary = target .. '.tmp'
        local fs = self.fs
        local created, directoryError = fs.createDirectory(target:match('^(.*)/'))
        assert(created, 'Cannot create save directory: ' .. tostring(directoryError))
        FileIO.write(fs, temporary, bytes)
        assert(self:decode(temporary), 'Save verification failed')
        -- Publish only the inactive generation. The last committed file survives
        -- interruption during write, validation, removal or rename of its sibling.
        if fs.getInfo(target) then
            assert(fs.remove(target), 'Cannot replace inactive save generation')
        end
        assert(FileIO.rename(fs, temporary, target), 'Cannot commit save generation')
        return { generation = generation, version = self.version, path = target }
    end)
    return ok and true or nil, ok and metadata or tostring(metadata)
end

function Store:remove(slot, exact)
    local ok, failure = pcall(function()
        local a, b = self:paths(slot, exact)
        for _, path in ipairs({ a, b, a .. '.tmp', b .. '.tmp' }) do
            if self.fs.getInfo(path) then
                assert(self.fs.remove(path), 'Cannot remove save: ' .. path)
            end
        end
    end)
    return ok and true or nil, not ok and tostring(failure) or nil
end

return Store
