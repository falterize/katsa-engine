local Runtime = require('source.engine.core.runtime')
local FrameLoop = require('source.engine.core.frameLoop')
local Deadline = require('source.engine.core.timing.deadline')

local Tests = {}

function Tests.run(tester)
    local original = katsa
    local frameDelta = Runtime.frameDelta
    local activeScene = Runtime.activeScene
    local limit, policy, dirty, timings =
        Runtime.frameRateLimit,
        Runtime.canReuseWindowFrame,
        Runtime.windowFrameDirty,
        Runtime.timings
    local elapsed, slept, draws, statsOpen, work = 0, 0, 0, false, 0.001
    local ok, failure = pcall(function()
        katsa = {
            timer = {
                getTime = function()
                    return elapsed
                end,
                step = function()
                    return 1 / 240
                end,
                sleep = function(seconds)
                    slept = slept + seconds
                    elapsed = elapsed + seconds
                end,
            },
            event = {
                pump = function() end,
                poll = function()
                    return function() end
                end,
            },
            window = {
                hasFocus = function()
                    return true
                end,
            },
            graphics = {
                isActive = function()
                    return true
                end,
                origin = function() end,
                getBackgroundColor = function()
                    return 0, 0, 0, 1
                end,
                clear = function() end,
                present = function()
                    elapsed = elapsed + 0.0005
                end,
            },
            update = function()
                elapsed = elapsed + work
            end,
            draw = function()
                draws = draws + 1
                elapsed = elapsed + (statsOpen and 0.001 or 0.0005)
            end,
        }
        Runtime.frameRateLimit, Runtime.canReuseWindowFrame, Runtime.windowFrameDirty =
            240, nil, false
        Runtime.activeScene = nil
        local tick = FrameLoop.run()
        tick()
        tester:check(
            math.abs(elapsed - 1 / 240) < 0.000001 and slept > 0,
            'Hidden Stats cannot turn a paced light scene into an unlimited busy loop'
        )
        statsOpen = true
        local started = elapsed
        tick()
        tester:check(
            math.abs(elapsed - started - 1 / 240) < 0.000001 and draws == 2,
            'Opening Stats preserves the same frame ceiling without dropping rendered frames'
        )
        tester:check(
            Runtime.timings.sleep > 0 and Runtime.timings.present > 0,
            'Pacing sleeps after presentation instead of spinning or adding work to the GPU'
        )
        Runtime.frameRateLimit, slept = 0, 0
        started = elapsed
        tick()
        tester:check(
            slept == 0 and elapsed - started < 1 / 240,
            'A zero project limit restores fully uncapped foreground rendering'
        )
        Runtime.frameRateLimit, work, slept = 240, 0.02, 0
        tick()
        tester:check(slept == 0, 'A frame already over budget receives no pacing delay')
        work, slept, Runtime.frameRateLimit = 0.001, 0, 0
        local scene = { settings = { frameRateLimit = 240 } }
        Runtime.activeScene = function()
            return scene
        end
        tick()
        tester:check(
            slept > 0,
            'Starter scene preview applies its own limit in the uncapped example collection'
        )
        scene, slept = { settings = {} }, 0
        tick()
        tester:check(slept == 0, 'Switching to another scene restores its original uncapped policy')
        scene, slept, Runtime.frameRateLimit = { settings = { frameRateLimit = 0 } }, 0, 240
        tick()
        tester:check(slept == 0, 'An explicit zero scene limit overrides a project default')
        tester:check(
            not pcall(Runtime.validateFrameRateLimit, -1)
                and not pcall(Runtime.validateFrameRateLimit, 0.5)
                and not pcall(Runtime.validateFrameRateLimit, math.huge),
            'Invalid frame limits are rejected before rendering starts'
        )
        local attempts, requested = 0, 0
        local timer = {
            getTime = function()
                return elapsed
            end,
            sleep = function(seconds)
                requested = seconds
                elapsed = elapsed + math.floor(seconds * 1000) / 1000
            end,
        }
        local target = elapsed + 0.00075
        Deadline.waitUntil(target, timer, function()
            return false
        end)
        tester:check(
            elapsed >= target and requested >= 0.001,
            'Sub-millisecond fallback cannot truncate to a zero-length wait'
        )
        target = elapsed + 0.002
        Deadline.waitUntil(target, timer, function(seconds)
            attempts = attempts + 1
            elapsed = attempts == 1 and elapsed + seconds / 2 or target
            return true
        end)
        tester:check(
            attempts == 2 and elapsed >= target,
            'An early wake is checked against the deadline before the next frame'
        )
        Runtime.frameRateLimit, Runtime.activeScene, work = 240, nil, 0
        local eventWork = 0.0005
        katsa.event.pump = function()
            elapsed = elapsed + eventWork
        end
        tick()
        eventWork = 0
        tick()
        tester:check(
            math.abs(Runtime.frameDelta - 1 / 240) < 0.000001,
            'FPS uses equal frame boundaries instead of fluctuating event-pump offsets'
        )
    end)
    katsa = original
    Runtime.frameDelta = frameDelta
    Runtime.activeScene = activeScene
    Runtime.frameRateLimit, Runtime.canReuseWindowFrame, Runtime.windowFrameDirty, Runtime.timings =
        limit, policy, dirty, timings
    assert(ok, failure)
end

return Tests
