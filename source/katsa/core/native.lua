-- Locates native shared libraries on every supported platform.
--
-- Search order for a logical name such as 'SDL2':
--   1. KATSA_LIB_DIR (environment), 2. `lib/` next to the executable (distribution layout),
--   3. the loader's default path (system packages, Android's app libs).
-- A library is loaded once and cached. Failure returns nil plus every attempted name.
local ffi = require('ffi')

local Native = { directories = {}, cache = {} }

local candidates = {
    SDL2 = {
        Windows = { 'SDL2.dll' },
        Linux = { 'libSDL2-2.0.so.0', 'libSDL2.so' },
        OSX = { 'libSDL2-2.0.0.dylib', 'libSDL2.dylib', 'SDL2.framework/SDL2' },
        Android = { 'libSDL2.so' },
    },
    OpenAL = {
        Windows = { 'OpenAL32.dll', 'soft_oal.dll' },
        Linux = { 'libopenal.so.1', 'libopenal.so' },
        OSX = { 'libopenal.1.dylib', '/System/Library/Frameworks/OpenAL.framework/OpenAL' },
        Android = { 'libopenal.so' },
    },
    FreeType = {
        Windows = { 'freetype.dll', 'libfreetype-6.dll' },
        Linux = { 'libfreetype.so.6', 'libfreetype.so' },
        OSX = { 'libfreetype.6.dylib', 'libfreetype.dylib' },
        Android = { 'libfreetype.so' },
    },
    Box2D = {
        Windows = { 'katsa_box2d.dll' },
        Linux = { 'libkatsa_box2d.so' },
        OSX = { 'libkatsa_box2d.dylib' },
        Android = { 'libkatsa_box2d.so' },
    },
    Net = {
        Windows = { 'katsa_net.dll' },
        Linux = { 'libkatsa_net.so' },
        OSX = { 'libkatsa_net.dylib' },
        Android = { 'libkatsa_net.so' },
    },
    Katsa = {
        Windows = { 'katsa_native.dll' },
        Linux = { 'libkatsa_native.so' },
        OSX = { 'libkatsa_native.dylib' },
        Android = { 'libkatsa_native.so' },
    },
}

-- 'Windows', 'Linux', 'OSX' or 'Android'.
function Native.os()
    if Native._os then
        return Native._os
    end
    local name = jit.os
    if name == 'Linux' and (os.getenv('ANDROID_ROOT') or os.getenv('ANDROID_DATA')) then
        name = 'Android'
    end
    Native._os = name
    return name
end

function Native.addDirectory(path)
    table.insert(Native.directories, 1, path)
end

local function separator()
    return Native.os() == 'Windows' and '\\' or '/'
end

function Native.load(name)
    if Native.cache[name] ~= nil then
        return Native.cache[name] or nil
    end
    local names = assert(candidates[name],
        'Unknown native library: ' .. tostring(name))[Native.os()]
        or {}
    local tried = {}
    local directories = {}
    local override = os.getenv('KATSA_LIB_DIR')
    if override and override ~= '' then
        directories[#directories + 1] = override
    end
    for _, directory in ipairs(Native.directories) do
        directories[#directories + 1] = directory
    end
    for _, directory in ipairs(directories) do
        for _, file in ipairs(names) do
            local path = directory .. separator() .. file
            tried[#tried + 1] = path
            local ok, library = pcall(ffi.load, path)
            if ok then
                Native.cache[name] = library
                return library
            end
        end
    end
    for _, file in ipairs(names) do
        tried[#tried + 1] = file
        local ok, library = pcall(ffi.load, file)
        if ok then
            Native.cache[name] = library
            return library
        end
    end
    Native.cache[name] = false
    return nil, 'Cannot load ' .. name .. '; tried: ' .. table.concat(tried, ', ')
end

function Native.require(name)
    return assert(Native.load(name))
end

return Native
