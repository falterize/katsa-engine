-- Run from the project root: lua source/tests/headless/parenting.lua
-- TeX Lua can also run this suite; no LÖVE graphics calls are required.
unpack = unpack or table.unpack
local count = 0
require('source.tests.integration.parenting')({
    check = function(_, condition, message)
        assert(condition, message)
        count = count + 1
        print('PASS ' .. message)
    end,
})
print('PASSED ' .. count .. ' behavior assertions')
