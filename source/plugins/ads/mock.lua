-- Development provider: a fake ad that "plays" for a moment, then rewards.
-- config.mockDuration (seconds, default 1.5), config.mockSkip (true = user closes early).
local Mock = { ready = false, remaining = nil, callback = nil }

function Mock.load(_, done)
    Mock.ready = true
    done(true)
end

function Mock.isReady()
    return Mock.ready
end

function Mock.show(config, done)
    Mock.ready = false
    Mock.callback = done
    Mock.skip = config.mockSkip == true
    Mock.remaining = config.mockDuration or 1.5
end

function Mock.update(dt)
    if Mock.remaining then
        Mock.remaining = Mock.remaining - dt
        if Mock.remaining <= 0 then
            local callback = Mock.callback
            Mock.remaining, Mock.callback = nil, nil
            callback({ rewarded = not Mock.skip })
        end
    end
end

return Mock
