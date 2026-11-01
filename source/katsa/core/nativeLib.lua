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
void* katsa_font_load(const uint8_t* data, int size);
void katsa_font_free(void* font);
float katsa_font_scale(void* font, float em_pixels);
void katsa_font_vmetrics(void* font, int* ascent, int* descent, int* line_gap);
int katsa_font_glyph_index(void* font, int codepoint);
void katsa_font_hmetrics(void* font, int codepoint, int* advance, int* lsb);
int katsa_font_kern(void* font, int cp1, int cp2);
uint8_t* katsa_font_bitmap(void* font, int codepoint, float scale, int* w, int* h, int* xoff, int* yoff);
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

-- Fonts -----------------------------------------------------------------------------------------

-- Returns a handle (freed on garbage collection) or nil, message.
function Lib.fontLoad(data)
    local handle = lib().katsa_font_load(data, #data)
    if handle == nil then
        return nil, 'Could not parse font data (only TrueType outlines are supported)'
    end
    return ffi.gc(handle, lib().katsa_font_free)
end

local ints = ffi.new('int[6]')

function Lib.fontScale(font, em)
    return
    lib().katsa_font_scale(font, em)
end

function Lib.fontVMetrics(font)
    lib().katsa_font_vmetrics(font, ints, ints + 1, ints + 2)
    return ints[0], ints[1], ints[2]
end

function Lib.fontHasGlyph(font,
    codepoint) return lib().katsa_font_glyph_index(font, codepoint) ~= 0 end
function Lib.fontHMetrics(font, codepoint)
    lib().katsa_font_hmetrics(font, codepoint, ints, ints + 1)
    return ints[0], ints[1]
end

function Lib.fontKern(font, a, b)
    return
    lib().katsa_font_kern(font, a, b)
end
-- Returns an 8-bit coverage buffer (copied, owned by Lua), width, height, xoffset, yoffset; or nil for blank glyphs.
function Lib.fontBitmap(font, codepoint, scale)
    local pointer = lib().katsa_font_bitmap(font, codepoint, scale, ints, ints + 1, ints + 2,
        ints + 3)
    if pointer == nil then
        return nil
    end
    local w, h = ints[0], ints[1]
    local copy = ffi.new('uint8_t[?]', w * h)
    ffi.copy(copy, pointer, w * h)
    lib().katsa_free(pointer)
    return copy, w, h, ints[2], ints[3]
end

return Lib
