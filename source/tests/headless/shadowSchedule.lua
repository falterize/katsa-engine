local count = 0
require('source.tests.integration.shadowSchedule')({
    check = function(_, ok, msg)
        assert(ok, msg)
        count = count + 1
        print('PASS ' .. msg)
    end,
})
print('PASSED ' .. count .. ' shadow scheduling assertions')
