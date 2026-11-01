require('source.tests.integration.luaCompatibility')
love = { timer = { getTime = os.clock } }
-- Only the backend clock is supplied; Oimo itself runs without mocks.
local count = 0
require('source.tests.integration.contactLifecycle')({
    check = function(_, ok, msg)
        assert(ok, msg)
        count = count + 1
        print('PASS ' .. msg)
    end,
})
print('PASSED ' .. count .. ' real Oimo lifecycle assertions')
