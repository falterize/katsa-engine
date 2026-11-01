-- Run from the project root: lua validation/tests/headless/parenting.lua
-- TeX Lua can also run this suite; no katsa graphics calls are required.
unpack = unpack or table.unpack
local count = 0
require('validation.tests.integration.parenting')({
    check = function(_, condition, message)
        assert(condition, message)
        count = count + 1
        print('PASS ' .. message)
    end,
})
print('PASSED ' .. count .. ' behavior assertions')
