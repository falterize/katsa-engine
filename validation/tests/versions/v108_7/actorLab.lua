-- The actorLab example: the workers' answer equals a sieve count and no frame stalls.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

local function sieve(limit)
    local composite, count = {}, 0
    for n = 2, limit do
        if not composite[n] then
            count = count + 1
            for m = n * n, limit, n do
                composite[m] = true
            end
        end
    end
    return count
end

function Tests:draw()
    self.frame = self.frame + 1
    if self.host then
        self.host:update(1 / 60, 1 / 60)
        self.host:draw()
        katsa.timer.sleep(0.004)
    end
    if self.frame == 1 then
        if os.getenv('KATSA_NO_THREADS') then
            local Binding = require('source.katsa.thread.binding')
            Binding.load = function() return nil, 'forced for the test' end
        end
        self.host = require('source.game.runtime.application').new(self.manager, 'actorLab')
        self.host:load()
        self.lab = self.host.demo
        self:check(self.lab and self.lab.actor and self.lab.actor:isRunning(), 'actorLab starts its Actor node')
        self.lab:startWorkers()
        self.frames = 0
    elseif self.lab.job then
        self.frames = self.frames + 1
        if self.frame > 1500 then
            self:check(false, 'the workers finished in time')
            katsa.event.quit()
        end
    elseif not self.finished then
        self.finished = true
        local expected = sieve(1800000)
        local result = self.lab.result or ''
        self:check(result:find(tostring(expected), 1, true) ~= nil, 'the workers count ' .. expected .. ' primes: ' .. result)
        self:check(self.lab.longest < 5, 'no frame stalled for seconds while workers counted')
        self.lab:ping()
        self.pinged = self.frame
    elseif self.lab.lastPong or self.frame > (self.pinged or 0) + 600 then
        self:check(self.lab.lastPong ~= nil, 'a worker answers a plain message with a message of its own')
        print('PASSED ' .. self.count .. ' v108.7 actorLab checks')
        katsa.event.quit()
    end
end

return Tests
