-- Standalone LuaJIT test runner for the katsa layer (no LÖVE required):
--   luajit source/tests/katsa/run.lua            -- from the repository root
-- GL checks are skipped with a notice when no EGL driver is available.
package.path = './?.lua;' .. package.path

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

local suites = { 'shaderTranslator', 'shaderCompile', 'scenesArchive' }
for _, name in ipairs(suites) do
    local ok, err = pcall(require('source.tests.katsa.' .. name), T)
    if not ok then
        failures = failures + 1
        print('FAIL suite ' .. name .. ': ' .. tostring(err))
    end
end
print(('katsa: %d passed, %d failed, %d skipped'):format(passes, failures, skipped))
os.exit(failures == 0 and 0 or 1)
