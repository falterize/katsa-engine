return function(test)
    local Schedule = require('source.engine.graphics.shadows.shadowSchedule')

    local function count(hz, delta, frames)
        local now, previous, deadline, updates = 1, 1, 0, 0
        for frame = 1, frames do
            now = now + delta(frame)
            local due, tolerance = Schedule.due(deadline, now, previous, hz)
            previous = now
            if due then
                updates = updates + 1
                deadline = Schedule.advance(deadline, now, tolerance, hz)
            end
        end
        return updates
    end
    test:check(
        count(60, function(i)
            return 1 / 60 + (i % 2 == 0 and 0.0002 or -0.0002)
        end, 120) == 120,
        '60 Hz scheduling tolerates frame jitter without alternating skipped frames'
    )
    local thirty = count(30, function()
        return 1 / 60
    end, 120)
    test:check(
        thirty >= 59 and thirty <= 61,
        '30 Hz shadows retain their requested cadence at 60 FPS'
    )
    local sixty = count(60, function()
        return 1 / 120
    end, 240)
    test:check(sixty >= 119 and sixty <= 121, '60 Hz shadows remain throttled at 120 FPS')
    local nextDeadline = Schedule.advance(1, 2, 0, 60)
    test:check(
        nextDeadline > 2 and nextDeadline < 2.02,
        'Long stalls skip missed deadlines without catch-up render bursts'
    )
end
