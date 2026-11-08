local ffi = require('ffi')
-- Parenthesize the read result: katsa also returns the byte count, whereas cdef
-- must receive only the header string.
ffi.cdef((assert(katsa.filesystem.read('vendor/joltPhysics/include/joltc.ffi.h'))))
local platformName, architectureName = katsa.system.getOS(), ffi.arch
local platform = ({ Windows = 'win', Linux = 'linux', Android = 'android', ['OS X'] = 'osx' })[platformName]
local architecture = ({ x64 = 'x64', arm64 = 'arm64', arm = 'arm' })[architectureName]
assert(platform and architecture, 'No Jolt binary for ' .. platformName .. '/' .. architectureName)
local filename = platformName == 'Windows' and 'joltc.dll'
    or platformName == 'OS X' and 'libjoltc.dylib'
    or 'libjoltc.so'
local relative = 'vendor/joltPhysics/native/' .. platform .. '-' .. architecture .. '/' .. filename
local bytes = assert(katsa.filesystem.read(relative), 'Missing Jolt native library: ' .. relative)
local hash = require('source.engine.core.fingerprint').of(bytes)
local folder = 'native-cache/joltc-' .. hash
assert(katsa.filesystem.createDirectory(folder))
local target = folder .. '/' .. filename
local old = katsa.filesystem.read(target)
-- A content-addressed path lets multiple project versions share the same
-- verified binary without trying to replace a DLL already loaded by Windows.
if old ~= bytes then
    assert(katsa.filesystem.write(target, bytes))
end
local lib
if platformName == 'Android' then
    -- Android 10+ may forbid dlopen from writable application storage. Custom
    -- APKs should package the matching library in their ABI native-lib directory.
    local ok, packaged = pcall(ffi.load, 'joltc')
    if ok then
        lib = packaged
    end
end
lib = lib
    or require('source.katsa.core.native').loadFile(katsa.filesystem.getSaveDirectory() .. '/' .. target)
assert(lib.JPH_Init(), 'Jolt initialization failed')
-- Keep the library alive for the entire Lua state; worlds own their native handles.
return { ffi = ffi, C = lib, hash = hash, platform = platform .. '-' .. architecture }
