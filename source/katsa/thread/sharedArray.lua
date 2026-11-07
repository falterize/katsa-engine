-- SharedArray: a typed array in memory shared between threads, plain FFI access in every state.
--
--   local grid = katsa.thread.SharedArray.new('uint8_t', width * height)
--   grid[0] = 1                         -- 0-based like C; grid.count, grid.data (the pointer)
--   worker:send('grid', { handle = grid:getHandle(), type = 'uint8_t', count = grid.count })
--   -- in the worker:
--   local grid = SharedArray.attach(data.handle, data.type, data.count)
--
-- No locking is implied: partition the work so threads write different elements, or synchronize
-- through the atomic helpers on int32 arrays (`add`, `compareAndSet`, `load`, `store`). The block
-- is reference counted: `attach` retains it, `release` (or garbage collection) lets go of it.
local ffi = require('ffi')
local Binding = require('source.katsa.thread.binding')

local SharedArray = {}
SharedArray.__index = function(self, key)
    if type(key) == 'number' then
        return self.data[key]
    end
    return SharedArray[key]
end
SharedArray.__newindex = function(self, key, value)
    if type(key) == 'number' then
        self.data[key] = value
    else
        rawset(self, key, value)
    end
end
SharedArray.__len = function(self)
    return self.count
end

local function wrap(library, handle, ctype, count)
    local self = setmetatable({
        _library = library,
        _handle = handle,
        type = ctype,
        count = count,
    }, SharedArray)
    rawset(self, 'data', ffi.cast(ctype .. '*', library.kt_shared_data(handle)))
    -- The collector releases the reference when the Lua object goes away.
    rawset(self, '_guard', ffi.gc(ffi.cast('void*', handle), function(pointer)
        library.kt_shared_release(pointer)
    end))
    return self
end

-- A zero-filled array of `count` elements of C type `ctype` ('double', 'int32_t', 'uint8_t', ...).
function SharedArray.new(ctype, count)
    local library = assert(Binding.load())
    local size = ffi.sizeof(ctype) * count
    local handle = library.kt_shared_new(size)
    assert(handle ~= nil, 'Out of memory for a shared array of ' .. size .. ' bytes')
    return wrap(library, handle, ctype, count)
end

-- Opens a block another thread shared (a number from getHandle()).
function SharedArray.attach(handle, ctype, count)
    local library = assert(Binding.load())
    local pointer = ffi.cast('void*', handle)
    library.kt_shared_retain(pointer)
    return wrap(library, pointer, ctype, count)
end

-- The block's address as a number, safe to send in a message.
function SharedArray:getHandle()
    return tonumber(ffi.cast('uintptr_t', self._handle))
end

function SharedArray:getByteSize()
    return tonumber(self._library.kt_shared_size(self._handle))
end

-- Threads holding the block.
function SharedArray:getReferences()
    return self._library.kt_shared_refs(self._handle)
end

function SharedArray:release()
    if self._guard then
        ffi.gc(self._guard, nil)
        self._library.kt_shared_release(self._handle)
        rawset(self, '_guard', nil)
    end
end

-- Atomic operations on slot `index` (0-based) of an int32_t array.
function SharedArray:load(index)
    return self._library.kt_atomic_load(self.data + index)
end

function SharedArray:store(index, value)
    self._library.kt_atomic_store(self.data + index, value)
end

function SharedArray:add(index, amount)
    return self._library.kt_atomic_add(self.data + index, amount)
end

function SharedArray:compareAndSet(index, expected, desired)
    return self._library.kt_atomic_cas(self.data + index, expected, desired) ~= 0
end

return SharedArray
