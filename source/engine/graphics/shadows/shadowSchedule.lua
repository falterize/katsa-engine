-- Fixed-phase deadlines avoid the old now+period cadence slipping a frame.
local Schedule = {}

function Schedule.due(deadline, clock, previous, hz)
    local period = 1 / hz
    local delta = previous and math.max(0, clock - previous) or 0
    local tolerance = math.min(period * 0.25, delta * 0.25)
    return deadline == 0 or clock + tolerance >= deadline, tolerance
end

function Schedule.advance(deadline, clock, tolerance, hz)
    local period = 1 / hz
    if deadline == 0 then
        return clock + period
    end
    local steps = math.max(1, math.floor((clock + tolerance - deadline) / period) + 1)
    return deadline + steps * period
end

return Schedule
