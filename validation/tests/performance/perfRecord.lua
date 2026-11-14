-- `--perf-record`: measures the same scenes as `--test-perf` and rewrites budgets.lua.
local Perf = require('validation.tests.performance.perf')
local Recorder = setmetatable({}, { __index = Perf })
Recorder.__index = Recorder

function Recorder.new(manager)
    local self = Perf.new(manager)
    self.mode = 'record'
    return setmetatable(self, Recorder)
end

return Recorder
