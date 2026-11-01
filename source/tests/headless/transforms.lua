require('source.tests.integration.luaCompatibility')
katsa = { timer = { getTime = os.clock } }
local count = 0
local test = {
    check = function(_, ok, msg)
        assert(ok, msg)
        count = count + 1
        print('PASS ' .. msg)
    end,
}
require('source.tests.integration.spatialTransforms')(test)
require('source.tests.integration.physicsTransforms')(test)
print('PASSED ' .. count .. ' spatial and real Oimo transform assertions')
