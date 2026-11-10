local Runtime = require('./runtime')
local Deadline = require('./timing.deadline')

local FrameLoop = {}

local SLOW_EVENTS_MS = 30

function FrameLoop.run()
    if katsa.load then
        katsa.load(katsa.arg.parseGameArguments(arg), arg)
    end
    if katsa.timer then
        katsa.timer.step()
    end
    local timings = { events = 0, update = 0, draw = 0, present = 0, sleep = 0 }
    Runtime.timings = timings
    local previousStarted
    local slowName, slowTime = 'pump', 0
    return function()
        local started = katsa.timer.getTime()
        -- Measure at the same boundary each frame. Measuring after event pumping
        -- makes a short event queue look like an FPS spike after a long one.
        Runtime.frameDelta = previousStarted and started - previousStarted or nil
        previousStarted = started
        if katsa.event then
            katsa.event.pump()
            slowName, slowTime = 'pump', katsa.timer.getTime() - started
            for name, a, b, c, d, e, f in katsa.event.poll() do
                if name == 'quit' and (not katsa.quit or not katsa.quit()) then
                    return a or 0
                end
                local before = katsa.timer.getTime()
                katsa.handlers[name](a, b, c, d, e, f)
                local spent = katsa.timer.getTime() - before
                if spent > slowTime then
                    slowName, slowTime = name, spent
                end
            end
        end
        local updated = katsa.timer.getTime()
        local events = (updated - started) * 1000
        -- A long event phase is either the OS (the pump) or one handler; say which.
        if events > SLOW_EVENTS_MS and katsa.log then
            katsa.log.warn(
                ('Slow event phase: %.0f ms, longest part "%s" %.0f ms'):format(
                    events,
                    slowName,
                    slowTime * 1000
                ),
                'Events',
                false
            )
        end
        local dt = katsa.timer.step()
        if katsa.update then
            katsa.update(dt)
        end
        local drawn = katsa.timer.getTime()
        local update = (drawn - updated) * 1000
        local draw, present, sleep = 0, 0, 0
        local reused = false
        if not Runtime.headless and katsa.graphics and katsa.graphics.isActive() then
            reused = not Runtime.windowFrameDirty
                    and Runtime.canReuseWindowFrame
                    and Runtime.canReuseWindowFrame()
                or false
            if not reused then
                katsa.graphics.origin()
                katsa.graphics.clear(katsa.graphics.getBackgroundColor())
                if katsa.draw then
                    katsa.draw()
                end
                local presented = katsa.timer.getTime()
                draw = (presented - drawn) * 1000
                katsa.graphics.present()
                present = (katsa.timer.getTime() - presented) * 1000
                Runtime.windowFrameDirty = false
            end
        end
        local limit = Runtime.frameRateLimit or 0
        local scene = Runtime.activeScene and Runtime.activeScene()
        if scene and scene.settings and scene.settings.frameRateLimit ~= nil then
            limit = scene.settings.frameRateLimit
        end
        -- Uncapped foreground rendering already performs useful work. The default
        -- 1 ms sleep adds scheduler jitter to every frame, even with VSync disabled.
        if Runtime.headless then
            -- A server holds its tick rate: wait out the rest of the frame, never spin.
            local idle = katsa.timer.getTime()
            local interval = 1 / math.max(limit, 1)
            if idle - started < interval then
                Deadline.waitUntil(started + interval, katsa.timer)
            end
            sleep = (katsa.timer.getTime() - idle) * 1000
        elseif not katsa.graphics.isActive() or not katsa.window.hasFocus() then
            local idle = katsa.timer.getTime()
            katsa.timer.sleep(0.01)
            sleep = (katsa.timer.getTime() - idle) * 1000
        elseif reused or limit > 0 then
            -- Only an explicit scene/project limit paces active rendering. Account for
            -- work already performed and yield instead of spinning on the CPU.
            local idle = katsa.timer.getTime()
            local interval = reused and 1 / 120 or 0
            if limit > 0 then
                interval = math.max(interval, 1 / limit)
            end
            local remaining = interval - (idle - started)
            if remaining > 0 then
                Deadline.waitUntil(started + interval, katsa.timer)
                sleep = (katsa.timer.getTime() - idle) * 1000
            end
        end
        timings.events, timings.update, timings.draw, timings.present, timings.sleep =
            events, update, draw, present, sleep
        timings.frameReused = reused
    end
end

return FrameLoop
