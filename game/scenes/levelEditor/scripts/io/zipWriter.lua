-- Stored (uncompressed) ZIP writer. The engine only reads ZIP (`source/katsa/core/archive.lua`);
-- a location file is written here and read back by that reader, so the layout follows what it
-- expects: local headers, a central directory and an end record, STORE entries only, no ZIP64.
local Crc32 = require('./crc32')

local ZipWriter = {}
ZipWriter.__index = ZipWriter

local char, concat = string.char, table.concat

local MAX = 0xFFFF
local DOS_DATE = 33 -- 1980-01-01: archives stay byte-identical for identical input
local DOS_TIME = 0
local UTF8_FLAG = 0x0800

local function u16(value)
    return char(value % 256, math.floor(value / 256) % 256)
end

local function u32(value)
    return char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    )
end

function ZipWriter.new()
    return setmetatable({ entries = {}, names = {}, size = 0 }, ZipWriter)
end

local function clean(name)
    name = tostring(name):gsub('\\', '/'):gsub('^/+', '')
    assert(name ~= '' and not name:find('%.%./', 1) and name ~= '..', 'Invalid ZIP entry name')
    return name
end

-- Adds a file. `data` is the exact byte content.
function ZipWriter:add(name, data)
    name = clean(name)
    assert(name:sub(-1) ~= '/', 'A file entry name must not end with a slash: ' .. name)
    assert(not self.names[name], 'Duplicate ZIP entry: ' .. name)
    assert(type(data) == 'string', 'ZIP entry data must be a string: ' .. name)
    assert(#data < 0xFFFFFFFF, 'ZIP entry too large: ' .. name)
    self.names[name] = true
    self.entries[#self.entries + 1] = { name = name, data = data, crc = Crc32.of(data) }
    return self
end

-- Adds an explicit directory entry (so empty folders survive, like the project packers do).
function ZipWriter:addDirectory(name)
    name = clean(name):gsub('/+$', '') .. '/'
    if not self.names[name] then
        self.names[name] = true
        self.entries[#self.entries + 1] = { name = name, data = '', crc = 0, directory = true }
    end
    return self
end

-- Returns the whole archive as a string.
function ZipWriter:build()
    assert(#self.entries < MAX, 'Too many ZIP entries')
    local parts, directory, offset = {}, {}, 0
    for _, entry in ipairs(self.entries) do
        local name, size = entry.name, #entry.data
        local header = concat({
            'PK\3\4',
            u16(20), -- version needed
            u16(UTF8_FLAG),
            u16(0), -- method: stored
            u16(DOS_TIME),
            u16(DOS_DATE),
            u32(entry.crc),
            u32(size),
            u32(size),
            u16(#name),
            u16(0), -- extra length
            name,
        })
        parts[#parts + 1] = header
        parts[#parts + 1] = entry.data
        directory[#directory + 1] = concat({
            'PK\1\2',
            u16(20), -- version made by
            u16(20),
            u16(UTF8_FLAG),
            u16(0),
            u16(DOS_TIME),
            u16(DOS_DATE),
            u32(entry.crc),
            u32(size),
            u32(size),
            u16(#name),
            u16(0), -- extra
            u16(0), -- comment
            u16(0), -- disk
            u16(0), -- internal attributes
            u32(entry.directory and 0x10 or 0), -- external attributes
            u32(offset),
            name,
        })
        offset = offset + #header + size
    end
    local central = concat(directory)
    assert(offset + #central < 0xFFFFFFFF, 'Archive too large for plain ZIP')
    parts[#parts + 1] = central
    parts[#parts + 1] = concat({
        'PK\5\6',
        u16(0),
        u16(0),
        u16(#self.entries),
        u16(#self.entries),
        u32(#central),
        u32(offset),
        u16(0),
    })
    return concat(parts)
end

return ZipWriter
