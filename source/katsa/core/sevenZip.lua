-- 7z reader (.7z scene packages). Supports Copy, Deflate, LZMA and LZMA2 coders, including archives
-- with an LZMA-compressed header. Every folder (solid block) is unpacked on first access and
-- cached.
local Archive = require('source.katsa.core.archive')
local Inflate = require('source.katsa.core.inflate')
local Lzma = require('source.katsa.core.lzma')

local utf8 = require('source.katsa.core.utf8')

local byte, sub = string.byte, string.sub

local SevenZip = setmetatable({}, { __index = Archive })
SevenZip.__index = SevenZip

SevenZip.signature = '7z\188\175\39\28'

local ID = {
    End = 0x00, Header = 0x01, MainStreamsInfo = 0x04, FilesInfo = 0x05, PackInfo = 0x06,
    UnpackInfo = 0x07, SubStreamsInfo = 0x08, Size = 0x09, CRC = 0x0A, Folder = 0x0B,
    CodersUnpackSize = 0x0C, NumUnpackStream = 0x0D, EmptyStream = 0x0E, EmptyFile = 0x0F,
    Names = 0x11, EncodedHeader = 0x17,
}

local COPY, DEFLATE, LZMA, LZMA2 = '\0', '\4\1\8', '\3\1\1', '\33'

-- Byte reader

local Reader = {}
Reader.__index = Reader

local function newReader(data, position)
    return setmetatable({ data = data, position = position or 1 }, Reader)
end

function Reader:byte()
    local value = byte(self.data, self.position)
    assert(value, 'Truncated 7z header')
    self.position = self.position + 1
    return value
end

function Reader:bytes(count)
    local value = sub(self.data, self.position, self.position + count - 1)
    assert(#value == count, 'Truncated 7z header')
    self.position = self.position + count
    return value
end

function Reader:skip(count)
    self.position = self.position + count
end

-- 7z numbers: the leading one-bits of the first byte give the count of extra little-endian bytes.
function Reader:number()
    local first = self:byte()
    local mask, value = 0x80, 0
    for i = 0, 7 do
        if bit.band(first, mask) == 0 then
            return value + bit.band(first, mask - 1) * 2 ^ (8 * i)
        end
        value = value + self:byte() * 2 ^ (8 * i)
        mask = mask / 2
    end
    return value
end

function Reader:uint32()
    local b1, b2, b3, b4 = self:byte(), self:byte(), self:byte(), self:byte()
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- A vector of `count` bits, most significant bit first.
function Reader:bits(count)
    local result, current, mask = {}, 0, 0
    for i = 1, count do
        if mask < 1 then
            current, mask = self:byte(), 0x80
        end
        result[i] = bit.band(current, mask) ~= 0
        mask = mask / 2
    end
    return result
end

function Reader:definedBits(count)
    if self:byte() ~= 0 then
        local all = {}
        for i = 1, count do
            all[i] = true
        end
        return all
    end
    return self:bits(count)
end

-- Header structures

local function readPackInfo(reader)
    local info = { position = reader:number(), sizes = {} }
    local count = reader:number()
    while true do
        local id = reader:byte()
        if id == ID.End then
            break
        elseif id == ID.Size then
            for i = 1, count do
                info.sizes[i] = reader:number()
            end
        elseif id == ID.CRC then
            local defined = reader:definedBits(count)
            for i = 1, count do
                if defined[i] then
                    reader:uint32()
                end
            end
        else
            error('Unsupported 7z pack info property: ' .. id)
        end
    end
    return info
end

local function readFolder(reader)
    local folder = { coders = {} }
    local totalIn, totalOut = 0, 0
    for i = 1, reader:number() do
        local flags = reader:byte()
        local coder = { id = reader:bytes(flags % 16) }
        coder.inStreams, coder.outStreams = 1, 1
        if flags >= 0x10 and flags % 0x20 >= 0x10 then
            coder.inStreams, coder.outStreams = reader:number(), reader:number()
        end
        if flags >= 0x20 and flags % 0x40 >= 0x20 then
            coder.properties = reader:bytes(reader:number())
        end
        folder.coders[i] = coder
        totalIn, totalOut = totalIn + coder.inStreams, totalOut + coder.outStreams
    end
    local bindPairs = totalOut - 1
    for _ = 1, bindPairs do
        reader:number()
        reader:number()
    end
    local packed = totalIn - bindPairs
    if packed > 1 then
        for _ = 1, packed do
            reader:number()
        end
    end
    folder.outStreams = totalOut
    return folder
end

-- Streams info: where packed data lives, how each folder unpacks and how it splits into files.
local function readStreamsInfo(reader)
    local streams = { pack = nil, folders = {}, subSizes = {}, counts = {} }
    while true do
        local id = reader:byte()
        if id == ID.End then
            break
        elseif id == ID.PackInfo then
            streams.pack = readPackInfo(reader)
        elseif id == ID.UnpackInfo then
            assert(reader:byte() == ID.Folder, 'Corrupt 7z header')
            local count = reader:number()
            assert(reader:byte() == 0, 'External 7z headers are not supported')
            for i = 1, count do
                streams.folders[i] = readFolder(reader)
            end
            assert(reader:byte() == ID.CodersUnpackSize, 'Corrupt 7z header')
            for _, folder in ipairs(streams.folders) do
                folder.unpackSizes = {}
                for j = 1, folder.outStreams do
                    folder.unpackSizes[j] = reader:number()
                end
                folder.unpackSize = folder.unpackSizes[#folder.unpackSizes]
            end
            local property = reader:byte()
            if property == ID.CRC then
                local defined = reader:definedBits(count)
                for i = 1, count do
                    if defined[i] then
                        reader:uint32()
                    end
                end
                property = reader:byte()
            end
            assert(property == ID.End, 'Corrupt 7z header')
        elseif id == ID.SubStreamsInfo then
            local property = reader:byte()
            for i = 1, #streams.folders do
                streams.counts[i] = 1
            end
            if property == ID.NumUnpackStream then
                for i = 1, #streams.folders do
                    streams.counts[i] = reader:number()
                end
                property = reader:byte()
            end
            if property == ID.Size then
                for i, folder in ipairs(streams.folders) do
                    local sizes, sum = {}, 0
                    for j = 1, streams.counts[i] - 1 do
                        sizes[j] = reader:number()
                        sum = sum + sizes[j]
                    end
                    if streams.counts[i] > 0 then
                        sizes[streams.counts[i]] = folder.unpackSize - sum
                    end
                    streams.subSizes[i] = sizes
                end
                property = reader:byte()
            else
                for i, folder in ipairs(streams.folders) do
                    streams.subSizes[i] = streams.counts[i] == 1 and { folder.unpackSize } or {}
                end
            end
            while property ~= ID.End do
                assert(property == ID.CRC, 'Unsupported 7z substream property: ' .. property)
                local missing = 0
                for i, folder in ipairs(streams.folders) do
                    missing = missing + (streams.counts[i] == 1 and 0 or streams.counts[i])
                end
                local defined = reader:definedBits(missing)
                for i = 1, missing do
                    if defined[i] then
                        reader:uint32()
                    end
                end
                property = reader:byte()
            end
        else
            error('Unsupported 7z streams property: ' .. id)
        end
    end
    if #streams.subSizes == 0 then
        for i, folder in ipairs(streams.folders) do
            streams.counts[i] = 1
            streams.subSizes[i] = { folder.unpackSize }
        end
    end
    return streams
end

-- Decoding

local function decodeFolder(folder, packed)
    assert(#folder.coders == 1, '7z archives with filter chains are not supported')
    local coder = folder.coders[1]
    if coder.id == COPY then
        return packed
    elseif coder.id == DEFLATE then
        return (Inflate.raw(packed, 1))
    elseif coder.id == LZMA then
        return Lzma.decode(coder.properties, packed, folder.unpackSize)
    elseif coder.id == LZMA2 then
        return Lzma.decode2(packed, folder.unpackSize)
    end
    error('Unsupported 7z compression method')
end

-- Packed bytes of every folder, in order; each folder here has a single packed stream.
local function folderData(data, streams, index)
    local offset = 32 + streams.pack.position
    for i = 1, index - 1 do
        offset = offset + streams.pack.sizes[i]
    end
    local packed = sub(data, offset + 1, offset + streams.pack.sizes[index])
    assert(#packed == streams.pack.sizes[index], 'Truncated 7z archive')
    return decodeFolder(streams.folders[index], packed)
end

local function fromUtf16(units)
    local chars, i = {}, 1
    while i <= #units do
        local unit = units[i]
        if unit >= 0xD800 and unit < 0xDC00 and units[i + 1] then
            unit = 0x10000 + (unit - 0xD800) * 1024 + (units[i + 1] - 0xDC00)
            i = i + 1
        end
        chars[#chars + 1] = utf8.char(unit)
        i = i + 1
    end
    return table.concat(chars)
end

local function decodeNames(raw, count)
    local names, position = {}, 1
    for i = 1, count do
        local units = {}
        while true do
            local low, high = byte(raw, position), byte(raw, position + 1)
            assert(low, 'Corrupt 7z file names')
            position = position + 2
            local unit = low + high * 256
            if unit == 0 then
                break
            end
            units[#units + 1] = unit
        end
        names[i] = fromUtf16(units)
    end
    return names
end

local function readFilesInfo(reader)
    local count = reader:number()
    local files = { count = count }
    while true do
        local id = reader:byte()
        if id == ID.End then
            break
        end
        local size = reader:number()
        local finish = reader.position + size
        if id == ID.EmptyStream then
            files.emptyStream = reader:bits(count)
        elseif id == ID.EmptyFile then
            local empties = 0
            for i = 1, count do
                if files.emptyStream and files.emptyStream[i] then
                    empties = empties + 1
                end
            end
            files.emptyFile = reader:bits(empties)
        elseif id == ID.Names then
            assert(reader:byte() == 0, 'External 7z names are not supported')
            files.names = decodeNames(reader:bytes(size - 1), count)
        end
        reader.position = finish
    end
    return files
end

local function readHeader(reader)
    local header = {}
    while true do
        local id = reader:byte()
        if id == ID.End then
            break
        elseif id == ID.MainStreamsInfo then
            header.streams = readStreamsInfo(reader)
        elseif id == ID.FilesInfo then
            header.files = readFilesInfo(reader)
        else
            error('Unsupported 7z header property: ' .. id)
        end
    end
    return header
end

-- Archive object

function SevenZip.new(data, label)
    assert(sub(data, 1, 6) == SevenZip.signature, 'Not a 7z archive: ' .. tostring(label))
    local fixed = newReader(data, 13)
    local nextOffset = fixed:uint32() + fixed:uint32() * 4294967296
    local nextSize = fixed:uint32() + fixed:uint32() * 4294967296
    assert(nextSize > 0, 'Empty 7z archive')
    local headerBytes = sub(data, 33 + nextOffset, 32 + nextOffset + nextSize)
    assert(#headerBytes == nextSize, 'Truncated 7z archive')
    local header
    while true do
        local headerReader = newReader(headerBytes, 1)
        local kind = headerReader:byte()
        if kind == ID.EncodedHeader then
            local streams = readStreamsInfo(headerReader)
            headerBytes = folderData(data, streams, 1)
        else
            assert(kind == ID.Header, 'Corrupt 7z header')
            header = readHeader(headerReader)
            break
        end
    end

    local self = setmetatable({
        data = data, label = label, files = {}, directories = { [''] = {} },
        streams = header.streams, folderCache = {},
    }, SevenZip)
    local files, streams = header.files, header.streams
    local folderIndex, streamIndex, offset = 1, 1, 0
    local emptyIndex = 0
    for i = 1, files and files.count or 0 do
        local name = Archive.normalize(files.names[i])
        if files.emptyStream and files.emptyStream[i] then
            emptyIndex = emptyIndex + 1
            local isFile = files.emptyFile and files.emptyFile[emptyIndex]
            if isFile then
                self.files[name] = { size = 0, empty = true }
            end
            self:_register(name, not isFile)
        else
            while streams.counts[folderIndex] == 0 or streamIndex > streams.counts[folderIndex] do
                folderIndex, streamIndex, offset = folderIndex + 1, 1, 0
            end
            local size = streams.subSizes[folderIndex][streamIndex]
            self.files[name] = { folder = folderIndex, offset = offset, size = size }
            self:_register(name, false)
            offset, streamIndex = offset + size, streamIndex + 1
        end
    end
    return self
end

function SevenZip:read(path)
    local file = self.files[Archive.normalize(path)]
    if not file then
        return nil
    elseif file.empty then
        return ''
    end
    local data = self.folderCache[file.folder]
    if not data then
        data = folderData(self.data, self.streams, file.folder)
        self.folderCache[file.folder] = data
    end
    return sub(data, file.offset + 1, file.offset + file.size)
end

return SevenZip
