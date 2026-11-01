-- File objects (filesystem.newFile). Writes and reads of real save files go through C stdio;
-- reads of files inside archives are served from memory.
local ffi = require('ffi')

ffi.cdef([[
typedef struct katsa_FILE katsa_FILE;
katsa_FILE* fopen(const char* path, const char* mode);
size_t fread(void* buffer, size_t size, size_t count, katsa_FILE* file);
size_t fwrite(const void* buffer, size_t size, size_t count, katsa_FILE* file);
int fflush(katsa_FILE* file);
int fclose(katsa_FILE* file);
int fseek(katsa_FILE* file, long offset, int origin);
long ftell(katsa_FILE* file);
]])

local C = ffi.C
local SEEK_SET, SEEK_END = 0, 2
local stdioModes = { r = 'rb', w = 'wb', a = 'ab' }

local File = {}
File.__index = File

-- `resolver` supplies the file system hooks: realPath(path, write) and readVirtual(path).
function File.new(filename, resolver)
    return setmetatable({ _name = filename, _resolver = resolver }, File)
end

local function closedError(self)
    return nil, 'File is not open'
end

function File:open(mode)
    if self._mode then
        return nil, 'File is already open'
    end
    local stdioMode = stdioModes[mode]
    if not stdioMode then
        return nil, 'Invalid file mode: ' .. tostring(mode)
    end
    local real = self._resolver.realPath(self._name, mode ~= 'r')
    if real then
        local handle = C.fopen(real, stdioMode)
        if handle == nil then
            return nil, 'Could not open file ' .. self._name
        end
        self._handle = handle
    elseif mode == 'r' then
        local data = self._resolver.readVirtual(self._name)
        if not data then
            return nil, 'Could not open file ' .. self._name .. ' (does not exist)'
        end
        self._memory, self._position = data, 0
    else
        return nil, 'Could not open file ' .. self._name .. ' for writing'
    end
    self._mode = mode
    return true
end

function File:isOpen()
    return self._mode ~= nil
end

function File:getMode()
    return self._mode or 'c'
end

function File:getFilename()
    return self._name
end

function File:getSize()
    if self._memory then
        return #self._memory
    elseif self._handle then
        local current = C.ftell(self._handle)
        C.fseek(self._handle, 0, SEEK_END)
        local size = tonumber(C.ftell(self._handle))
        C.fseek(self._handle, current, SEEK_SET)
        return size
    end
    return self._resolver.size(self._name)
end

function File:tell()
    if self._memory then
        return self._position
    elseif self._handle then
        return tonumber(C.ftell(self._handle))
    end
    return closedError(self)
end

function File:seek(position)
    if self._memory then
        self._position = math.max(0, math.min(position, #self._memory))
        return true
    elseif self._handle then
        return C.fseek(self._handle, position, SEEK_SET) == 0
    end
    return false
end

function File:isEOF()
    if self._memory then
        return self._position >= #self._memory
    elseif self._handle then
        local current = C.ftell(self._handle)
        C.fseek(self._handle, 0, SEEK_END)
        local atEnd = C.ftell(self._handle) <= current
        C.fseek(self._handle, current, SEEK_SET)
        return atEnd
    end
    return true
end

-- read([size]) -> contents, bytesRead. Without a size the rest of the file is returned.
function File:read(size)
    if self._mode ~= 'r' then
        return nil, 'File is not opened for reading'
    end
    if self._memory then
        local count = size or (#self._memory - self._position)
        local chunk = self._memory:sub(self._position + 1, self._position + count)
        self._position = self._position + #chunk
        return chunk, #chunk
    end
    local count = size or (self:getSize() - self:tell())
    local buffer = ffi.new('uint8_t[?]', math.max(count, 1))
    local got = tonumber(C.fread(buffer, 1, count, self._handle))
    return ffi.string(buffer, got), got
end

function File:write(data, size)
    if self._mode ~= 'w' and self._mode ~= 'a' then
        return nil, 'File is not opened for writing'
    end
    if type(data) == 'table' and data.getString then
        data = data:getString()
    end
    size = size or #data
    if tonumber(C.fwrite(data, 1, size, self._handle)) ~= size then
        return nil, 'Could not write to file ' .. self._name
    end
    return true
end

function File:flush()
    if self._handle then
        return C.fflush(self._handle) == 0
    end
    return true
end

function File:setBuffer()
    return true
end

function File:getBuffer()
    return 'none', 0
end

function File:lines()
    local contents = assert(self:read())
    return contents:gmatch('([^\r\n]*)\r?\n?')
end

function File:close()
    if not self._mode then
        return false
    end
    local ok = true
    if self._handle then
        ok = C.fclose(self._handle) == 0
    end
    self._handle, self._memory, self._position, self._mode = nil, nil, nil, nil
    return ok
end

function File:release()
    return self:close()
end

function File:type()
    return 'File'
end

function File:typeOf(name)
    return name == 'File' or name == 'Object'
end

return File
