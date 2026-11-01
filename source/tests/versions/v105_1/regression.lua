local Baseline = require('source.tests.versions.v102.runtime')
local Quality = require('source.engine.graphics.quality.renderQuality')

local Tests = {}

function Tests.new(manager)
    -- The historical suite explicitly tests the non-MSAA depth-prepass path.
    Quality.defaultSamples = function()
        return 0
    end
    return Baseline.new(manager)
end

return Tests
