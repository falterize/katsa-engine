unpack = unpack or table.unpack
local count = 0
require('source.tests.integration.nodeLifecycle')({
    check = function(_, ok, msg)
        assert(ok, msg)
        count = count + 1
        print('PASS ' .. msg)
    end,
})
print('PASSED ' .. count .. ' node lifecycle assertions')
