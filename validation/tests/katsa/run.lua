-- Standalone LuaJIT test runner for the katsa layer (no katsa required):
--   luajit validation/tests/katsa/run.lua            -- from the repository root
-- GL checks are skipped with a notice when no EGL driver is available.
package.path = './?.lua;' .. package.path

package.path = './?/init.lua;' .. package.path
_G.require = require('source.katsa.core.relativeRequire').wrap(require)
local Nat = require('source.katsa.core.native')
Nat.addDirectory('native/build/' .. ({ Windows = 'windows', Linux = 'linux', OSX = 'macos' })[Nat.os()])
local failures, passes, skipped = 0, 0, 0
local T = {}

function T.check(condition, message)
    if condition then
        passes = passes + 1
    else
        failures = failures + 1
        print('FAIL ' .. message)
    end
end

function T.skip(message)
    skipped = skipped + 1
    print('SKIP ' .. message)
end

local suites = {
    'shaderTranslator',
    'shaderCompile',
    'scenesArchive',
    'imageData',
    'graphics',
    'physics',
    'data',
    'openal',
    'audio',
    'sevenZip',
    'net',
    'pathfinding',
    'netGame',
    'vehicle',
    'folderNodes',
    'ads',
    'carsGame',
    'profiler',
}
for _, name in ipairs(suites) do
    local ok, err = pcall(require('validation.tests.katsa.' .. name), T)
    if not ok and tostring(err):find('Cannot load', 1, true) then
        -- A system library (SDL2, OpenAL) is not installed on this machine: not a code failure.
        T.skip('suite ' .. name .. ': ' .. tostring(err):match('Cannot load %w+'))
    elseif not ok then
        failures = failures + 1
        print('FAIL suite ' .. name .. ': ' .. tostring(err))
    end
end
print(('katsa: %d passed, %d failed, %d skipped'):format(passes, failures, skipped))
os.exit(failures == 0 and 0 or 1)
