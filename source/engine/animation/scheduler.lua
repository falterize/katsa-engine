local ipairs = require('source.engine.math.array').ipairs

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
    return setmetatable({ tracks = {}, members = {} }, Scheduler)
end

function Scheduler:add(track)
    if not self.members[track] then
        self.members[track] = true
        self.tracks[#self.tracks + 1] = track
    end
end

function Scheduler:update(dt)
    local count = #self.tracks
    for i = 1, count do
        local track = self.tracks[i]
        if track.target.destroyed or track.options.ramp and track.options.ramp.destroyed then
            track:destroy()
        elseif track.state == 'Playing' then
            track:update(dt)
        end
    end
    local write = 1
    for _, track in ipairs(self.tracks) do
        if track.state == 'Playing' or track.state == 'Paused' then
            self.tracks[write] = track
            write = write + 1
        else
            self.members[track] = nil
        end
    end
    for i = #self.tracks, write, -1 do
        self.tracks[i] = nil
    end
end

function Scheduler:release()
    for _, track in ipairs(self.tracks) do
        track:destroy()
    end
    self.tracks, self.members = {}, {}
end

return Scheduler
