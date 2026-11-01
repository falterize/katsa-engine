-- Byte buffer with the ByteData surface used by the engine.

local ffi = require('ffi')

local M = {}

local ByteData = {}
ByteData.__index = ByteData

function M.newByteData(source)
    local size = type(source) == 'number' and source or #source
    local buffer = ffi.new('uint8_t[?]', size)
    if type(source) == 'string' then
        ffi.copy(buffer, source, size)
    end
    return setmetatable({ _buffer = buffer, _size = size }, ByteData)
end

function ByteData:getSize()
    return self._size
end

function ByteData:getPointer()
    return self._buffer
end

function ByteData:getString()
    return ffi.string(self._buffer, self._size)
end

function ByteData:release() end

return M
