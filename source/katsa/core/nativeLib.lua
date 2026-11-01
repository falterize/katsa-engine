-- LuaJIT binding to katsa_native (filesystem, image codecs, Vorbis).
local ffi = require('ffi')
local Native = require('source.katsa.core.native')

ffi.cdef([[
int katsa_version(void);
void katsa_free(void* pointer);
int katsa_fs_stat(const char* path, int64_t* size, int64_t* modified);
int katsa_fs_mkdir(const char* path);
int katsa_fs_remove(const char* path);
int64_t katsa_fs_list(const char* path, char* buffer, int64_t capacity);
uint8_t* katsa_fs_read(const char* path, int64_t* size);
int64_t katsa_fs_read_range(const char* path, int64_t offset, uint8_t* buffer, int64_t length);
int katsa_fs_write(const char* path, const uint8_t* data, int64_t size, int append);
int katsa_exe_path(char* buffer, int capacity);
uint8_t* katsa_image_decode(const uint8_t* data, int size, int* width, int* height);
const char* katsa_image_error(void);
uint8_t* katsa_image_encode_png(const uint8_t* rgba, int width, int height, int* size);
int16_t* katsa_vorbis_decode(const uint8_t* data, int size, int* channels, int* rate, int* frames);
]])

local Lib = {}

local library, failure
function Lib.get()
    if library == nil then
        library, failure = Native.load('Katsa')
        library = library or false
    end
    return library or nil, failure
end

local function lib()
    return assert(Lib.get())
end

function Lib.available()
    return Lib.get() ~= nil
end

local size64, modified64 = ffi.new('int64_t[1]'), ffi.new('int64_t[1]')

-- Returns 'file', 'directory' or nil, plus size and modification time.
function Lib.stat(path)
    local kind = lib().katsa_fs_stat(path, size64, modified64)
    if kind == 0 then
        return nil
    end
    return kind == 2 and 'directory' or 'file', tonumber(size64[0]), tonumber(modified64[0])
end

function Lib.mkdir(path)
    return lib().katsa_fs_mkdir(path) == 0
end

function Lib.remove(path)
    return lib().katsa_fs_remove(path) == 0
end

function Lib.list(path)
    local capacity = 4096
    while true do
        local buffer = ffi.new('char[?]', capacity)
        local needed = tonumber(lib().katsa_fs_list(path, buffer, capacity))
        if needed < 0 then
            return nil
        end
        if needed <= capacity then
            local names, start = {}, 0
            while start < needed do
                local name = ffi.string(buffer + start)
                names[#names + 1] = name
                start = start + #name + 1
            end
            return names
        end
        capacity = needed + 16
    end
end

function Lib.read(path)
    local pointer = lib().katsa_fs_read(path, size64)
    if pointer == nil then
        return nil
    end
    local text = ffi.string(pointer, tonumber(size64[0]))
    lib().katsa_free(pointer)
    return text
end

function Lib.readRange(path, offset, length)
    local buffer = ffi.new('uint8_t[?]', math.max(length, 1))
    local got = tonumber(lib().katsa_fs_read_range(path, offset, buffer, length))
    if got < 0 then
        return nil
    end
    return ffi.string(buffer, got)
end

function Lib.write(path, data, append)
    return lib().katsa_fs_write(path, data, #data, append and 1 or 0) == 0
end

function Lib.exePath()
    local buffer = ffi.new('char[4096]')
    local length = lib().katsa_exe_path(buffer, 4096)
    return length > 0 and ffi.string(buffer, length) or nil
end

-- Decodes an encoded image to RGBA8 and returns a managed buffer, width, height.
function Lib.decodeImage(data)
    local width, height = ffi.new('int[1]'), ffi.new('int[1]')
    local pointer = lib().katsa_image_decode(data, #data, width, height)
    if pointer == nil then
        return nil, ffi.string(lib().katsa_image_error())
    end
    local bytes = width[0] * height[0] * 4
    local buffer = ffi.new('uint8_t[?]', bytes)
    ffi.copy(buffer, pointer, bytes)
    lib().katsa_free(pointer)
    return buffer, width[0], height[0]
end

function Lib.encodePng(buffer, width, height)
    local size = ffi.new('int[1]')
    local pointer = lib().katsa_image_encode_png(buffer, width, height, size)
    if pointer == nil then
        return nil
    end
    local text = ffi.string(pointer, size[0])
    lib().katsa_free(pointer)
    return text
end

-- Returns interleaved int16 samples (buffer), channels, sample rate and frame count.
function Lib.decodeVorbis(data)
    local channels, rate, frames = ffi.new('int[1]'), ffi.new('int[1]'), ffi.new('int[1]')
    local pointer = lib().katsa_vorbis_decode(data, #data, channels, rate, frames)
    if pointer == nil then
        return nil, 'Invalid Ogg Vorbis data'
    end
    local count = frames[0] * channels[0]
    local buffer = ffi.new('int16_t[?]', count)
    ffi.copy(buffer, pointer, count * 2)
    lib().katsa_free(pointer)
    return buffer, channels[0], rate[0], frames[0]
end

return Lib
