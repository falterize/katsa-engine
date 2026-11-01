local Paths = require('source.engine.scenes.paths')
local bit = require('bit')

local Archive = {}
local crcTable = {}
for value = 0, 255 do
    local crc = value
    for _ = 1, 8 do
        crc = bit.bxor(bit.rshift(crc, 1), bit.band(crc, 1) ~= 0 and 0xEDB88320 or 0)
    end
    crcTable[value] = crc
end

local function crc32(data)
    local crc = -1
    for index = 1, #data do
        crc = bit.bxor(bit.rshift(crc, 8), crcTable[bit.band(bit.bxor(crc, data:byte(index)), 255)])
    end
    return bit.bnot(crc)
end

local function integer(value, bytes)
    local out = {}
    for index = 1, bytes do
        out[index] = string.char(bit.band(value, 255))
        value = bit.rshift(value, 8)
    end
    return table.concat(out)
end

local function field(data, first, size)
    return data:sub(first, first + size - 1):match('^[^%z]*')
end

-- TAR is converted once, in memory, to stored ZIP entries. No files are extracted
-- to disk, and assets subsequently use the same VFS/cache path as native ZIP.
local function tarToZip(data)
    local files, central, offset, cursor, count = {}, {}, 0, 1, 0
    while cursor + 511 <= #data do
        local header = data:sub(cursor, cursor + 511)
        if header == string.rep('\0', 512) then
            break
        end
        local expected = tonumber(field(header, 149, 8):match('^%s*(%d+)'), 8)
        local checksum = 0
        for index = 1, 512 do
            checksum = checksum + (index >= 149 and index <= 156 and 32 or header:byte(index))
        end
        assert(expected == checksum, 'Invalid TAR header checksum')
        local name = field(header, 1, 100)
        local prefix = field(header, 346, 155)
        if prefix ~= '' then
            name = prefix .. '/' .. name
        end
        local size =
            assert(tonumber(field(header, 125, 12):match('^%s*(%d+)'), 8), 'Invalid TAR entry size')
        local kind = header:sub(157, 157)
        assert(cursor + 511 + size <= #data, 'Truncated TAR entry')
        if kind == '5' and (name == '.' or name == './') then
            assert(size == 0, 'TAR directories must have no payload')
        elseif kind == '0' or kind == '\0' or kind == '5' then
            local isDirectory = kind == '5'
            assert(not isDirectory or size == 0, 'TAR directories must have no payload')
            name = Paths.normalize(name)
            -- Empty categories need their own ZIP entries when no marker files exist.
            if isDirectory then
                name = name .. '/'
            end
            local content = data:sub(cursor + 512, cursor + 511 + size)
            local checksumBytes = integer(crc32(content), 4)
            local sizes = integer(size, 4) .. integer(size, 4)
            local common = integer(20, 2) .. integer(0x800, 2) .. string.rep('\0', 6)
            local lengths = integer(#name, 2) .. integer(0, 2)
            local entry = 'PK\3\4' .. common .. checksumBytes .. sizes .. lengths .. name .. content
            files[#files + 1] = entry
            central[#central + 1] = 'PK\1\2'
                .. integer(20, 2)
                .. common
                .. checksumBytes
                .. sizes
                .. lengths
                .. string.rep('\0', 6)
                .. integer(isDirectory and 0x10 or 0, 4)
                .. integer(offset, 4)
                .. name
            offset, count = offset + #entry, count + 1
        else
            error('Unsupported TAR entry; use regular USTAR files/directories or ZIP', 0)
        end
        cursor = cursor + 512 + math.ceil(size / 512) * 512
    end
    assert(count > 0 and count < 65536 and offset < 4294967296, 'Empty or oversized TAR archive')
    local directory = table.concat(central)
    files[#files + 1] = directory
    files[#files + 1] = 'PK\5\6'
        .. string.rep('\0', 4)
        .. integer(count, 2)
        .. integer(count, 2)
        .. integer(#directory, 4)
        .. integer(offset, 4)
        .. '\0\0'
    return katsa.filesystem.newFileData(table.concat(files), 'scene.zip')
end

function Archive.read(source)
    local data
    if type(source) ~= 'string' then
        data = source
    elseif source:match('^%a:') or source:match('^[/\\]') then
        local file, message = io.open(source, 'rb')
        assert(file, message)
        local bytes = file:read('*a')
        file:close()
        data = katsa.filesystem.newFileData(bytes, source:match('[^/\\]+$'))
    else
        data = katsa.filesystem.newFileData(source)
    end
    assert(
        data and data.typeOf and data:typeOf('FileData'),
        'Scene archive must be a path or FileData'
    )
    local name = data:getFilename():lower()
    if name:match('%.tar%.gz$') or name:match('%.tgz$') then
        return tarToZip(katsa.data.decompress('string', 'gzip', data))
    elseif name:match('%.tar$') then
        return tarToZip(data:getString())
    end
    return data
end

return Archive
