-- FileData: an immutable named byte string.
local ffi = require('ffi')

local FileData = {}
FileData.__index = FileData

function FileData:getString()
    return self._data
end

function FileData:getSize()
    return #self._data
end

function FileData:getFilename()
    return self._name
end

function FileData:getExtension()
    return self._name:match('%.([^%.]+)$')
end

function FileData:getPointer()
    return ffi.cast('const void*', self._data)
end

function FileData:getFFIPointer()
    return ffi.cast('const void*', self._data)
end

function FileData:clone()
    return setmetatable({ _data = self._data, _name = self._name }, FileData)
end

function FileData:release()
    return true
end

function FileData:type()
    return 'FileData'
end

function FileData:typeOf(name)
    return name == 'FileData' or name == 'Data' or name == 'Object'
end

function FileData.new(data, name)
    return setmetatable({ _data = data, _name = name }, FileData)
end

return FileData
