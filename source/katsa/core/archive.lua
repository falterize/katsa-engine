-- ZIP reader used for .katsa, .love and .zip projects and for archives appended to an executable.
--
-- Entries are read lazily. DEFLATE is decoded in pure Lua; STORE entries are returned as-is, which
-- is what the katsa packager writes for fast startup. Offsets are relative to the start of the
-- archive, so a ZIP appended to an executable (or any prefix) works without rewriting it.
local Inflate = require('source.katsa.core.inflate')

local byte, sub = string.byte, string.sub

local Archive = {}
Archive.__index = Archive

local function u16(s, p)
    return byte(s, p) + byte(s, p + 1) * 256
end

local function u32(s, p)
    return byte(s, p) + byte(s, p + 1) * 256 + byte(s, p + 2) * 65536 + byte(s, p + 3) * 16777216
end

local function normalize(path)
    path = path:gsub('\\', '/'):gsub('^/+', ''):gsub('/+$', '')
    return path
end
Archive.normalize = normalize

-- reader(offset, length) -> string | nil; size is the total length of the underlying file.
function Archive.new(reader, size, label)
    local tailSize = math.min(size, 65557)
    local tail = reader(size - tailSize, tailSize)
    assert(tail and #tail == tailSize, 'Cannot read archive: ' .. tostring(label))
    local eocd
    for i = #tail - 21, 1, -1 do
        if sub(tail, i, i + 3) == 'PK\5\6' then
            eocd = i
            break
        end
    end
    assert(eocd, 'Not a ZIP archive: ' .. tostring(label))
    local count = u16(tail, eocd + 10)
    local directorySize = u32(tail, eocd + 12)
    local directoryOffset = u32(tail, eocd + 16)
    assert(count ~= 0xFFFF and directoryOffset ~= 0xFFFFFFFF, 'ZIP64 archives are not supported')
    local eocdPosition = size - tailSize + eocd - 1
    -- Prefix (for example an executable) before the archive data.
    local base = eocdPosition - directorySize - directoryOffset
    assert(base >= 0, 'Corrupt ZIP directory: ' .. tostring(label))
    local directory = reader(base + directoryOffset, directorySize)
    assert(directory and #directory == directorySize, 'Cannot read ZIP directory')

    local self = setmetatable({
        reader = reader,
        base = base,
        label = label,
        files = {},
        directories = { [''] = {} },
    }, Archive)
    local p = 1
    for _ = 1, count do
        assert(sub(directory, p, p + 3) == 'PK\1\2', 'Corrupt ZIP directory entry')
        local method = u16(directory, p + 10)
        local compressed = u32(directory, p + 20)
        local uncompressed = u32(directory, p + 24)
        local nameLength = u16(directory, p + 28)
        local extraLength = u16(directory, p + 30)
        local commentLength = u16(directory, p + 32)
        local localOffset = u32(directory, p + 42)
        local name = sub(directory, p + 46, p + 45 + nameLength)
        p = p + 46 + nameLength + extraLength + commentLength
        local isDirectory = name:sub(-1) == '/'
        name = normalize(name)
        if name ~= '' then
            if not isDirectory then
                self.files[name] = {
                    method = method,
                    compressed = compressed,
                    size = uncompressed,
                    offset = localOffset,
                }
            end
            self:_register(name, isDirectory)
        end
    end
    return self
end

-- Records a path and every parent directory for listing.
function Archive:_register(name, isDirectory)
    local parent, leaf = name:match('^(.*)/([^/]+)$')
    if not parent then
        parent, leaf = '', name
    end
    if parent ~= '' and not self.directories[parent] then
        self:_register(parent, true)
    end
    local children = self.directories[parent]
    if not children[leaf] then
        children[leaf] = true
        children[#children + 1] = leaf
    end
    if isDirectory and not self.directories[name] then
        self.directories[name] = {}
    end
end

local SEVEN_ZIP_SIGNATURE = '7z\188\175\39\28'

function Archive.fromFile(path, nativeLib)
    local kind, size = nativeLib.stat(path)
    assert(kind == 'file', 'Archive not found: ' .. path)
    if nativeLib.readRange(path, 0, 6) == SEVEN_ZIP_SIGNATURE then
        return require('source.katsa.core.sevenZip').new(nativeLib.readRange(path, 0, size), path)
    end
    return Archive.new(function(offset, length)
        return nativeLib.readRange(path, offset, length)
    end, size, path)
end

function Archive.fromString(data, label)
    if sub(data, 1, 6) == SEVEN_ZIP_SIGNATURE then
        return require('source.katsa.core.sevenZip').new(data, label)
    end
    return Archive.new(function(offset, length)
        return sub(data, offset + 1, offset + length)
    end, #data, label or 'memory')
end

function Archive:info(path)
    path = normalize(path)
    local file = self.files[path]
    if file then
        return { type = 'file', size = file.size, modtime = 0, readonly = true }
    end
    if self.directories[path] then
        return { type = 'directory', size = 0, modtime = 0, readonly = true }
    end
    return nil
end

function Archive:read(path)
    local file = self.files[normalize(path)]
    if not file then
        return nil
    end
    local header = self.reader(self.base + file.offset, 30)
    assert(header and sub(header, 1, 4) == 'PK\3\4', 'Corrupt ZIP local header')
    local nameLength, extraLength = u16(header, 27), u16(header, 29)
    local raw = self.reader(self.base + file.offset + 30 + nameLength + extraLength,
        file.compressed)
    assert(raw and #raw == file.compressed, 'Truncated ZIP entry')
    if file.method == 0 then
        return raw
    elseif file.method == 8 then
        local data = Inflate.raw(raw, 1)
        assert(#data == file.size, 'ZIP entry size mismatch')
        return data
    end
    error('Unsupported ZIP compression method: ' .. file.method)
end

function Archive:list(path)
    local children = self.directories[normalize(path)]
    if not children then
        return nil
    end
    local names = {}
    for i, name in ipairs(children) do
        names[i] = name
    end
    return names
end

function Archive:has(path)
    return self.files[normalize(path)] ~= nil
end

return Archive
