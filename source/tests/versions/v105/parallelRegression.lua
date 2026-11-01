local Baseline = require('source.tests.versions.v104.runtime')
local Jobs = require('source.engine.physics.3d.backends.jolt.native.jobs')

local Tests = {}

function Tests.new(manager)
    local create = Jobs.create
    -- Exercise worker callbacks even in the baseline's small lifecycle fixtures.
    function Jobs.create(world, settings, callbacks)
        settings.parallelThreshold = 0
        return create(world, settings, callbacks)
    end
    local test = Baseline.new(manager)
    local draw = test.draw
    function test:draw()
        local ok, message = pcall(draw, self)
        Jobs.create = create
        assert(ok, message)
        print('V105 FORCED PARALLEL REGRESSION COMPLETE')
    end
    return test
end

return Tests
