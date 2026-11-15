-- Sends an agent to its points one after another, resting a moment at each.
local Patrol = {}
Patrol.__index = Patrol

function Patrol.new(agent, points, rest)
    local self = setmetatable({ agent = agent, points = points, index = 0, rest = rest or 1 }, Patrol)
    agent:connect('Arrived', function()
        self.timer = self.rest
    end)
    agent:connect('PathFailed', function()
        self.timer = self.rest
    end)
    self:advance()
    return self
end

function Patrol:advance()
    self.index = self.index % #self.points + 1
    self.timer = nil
    self.agent:setTarget(self.points[self.index])
end

function Patrol:update(dt)
    if self.timer then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            self:advance()
        end
    end
end

return Patrol
