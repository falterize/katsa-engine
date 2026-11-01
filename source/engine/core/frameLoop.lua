local Runtime = require('source.engine.core.runtime')
local Deadline = require('source.engine.core.timing.deadline')

local FrameLoop = {}

function FrameLoop.run()
    if love.load then
        love.load(love.arg.parseGameArguments(arg), arg)
    end
    if love.timer then
        love.timer.step()
    end
    local timings = { events = 0, update = 0, draw = 0, present = 0, sleep = 0 }
    Runtime.timings = timings
    local previousStarted
    return function()
        local started = love.timer.getTime()
        -- Measure at the same boundary each frame. Measuring after event pumping
        -- makes a short event queue look like an FPS spike after a long one.
        Runtime.frameDelta = previousStarted and started - previousStarted or nil
        previousStarted = started
        if love.event then
            love.event.pump()
            for name, a, b, c, d, e, f in love.event.poll() do
                if name == 'quit' and (not love.quit or not love.quit()) then
                    return a or 0
                end
                love.handlers[name](a, b, c, d, e, f)
            end
        end
        local updated = love.timer.getTime()
        local events = (updated - started) * 1000
        local dt = love.timer.step()
        if love.update then
            love.update(dt)
        end
        local drawn = love.timer.getTime()
        local update = (drawn - updated) * 1000
        local draw, present, sleep = 0, 0, 0
        local reused = false
        if love.graphics and love.graphics.isActive() then
            reused = not Runtime.windowFrameDirty
                    and Runtime.canReuseWindowFrame
                    and Runtime.canReuseWindowFrame()
                or false
            if not reused then
                love.graphics.origin()
                love.graphics.clear(love.graphics.getBackgroundColor())
                if love.draw then
                    love.draw()
                end
                local presented = love.timer.getTime()
                draw = (presented - drawn) * 1000
                love.graphics.present()
                present = (love.timer.getTime() - presented) * 1000
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
        if not love.graphics.isActive() or not love.window.hasFocus() then
            local idle = love.timer.getTime()
            love.timer.sleep(0.01)
            sleep = (love.timer.getTime() - idle) * 1000
        elseif reused or limit > 0 then
            -- Only an explicit scene/project limit paces active rendering. Account for
            -- work already performed and yield instead of spinning on the CPU.
            local idle = love.timer.getTime()
            local interval = reused and 1 / 120 or 0
            if limit > 0 then
                interval = math.max(interval, 1 / limit)
            end
            local remaining = interval - (idle - started)
            if remaining > 0 then
                Deadline.waitUntil(started + interval, love.timer)
                sleep = (love.timer.getTime() - idle) * 1000
            end
        end
        timings.events, timings.update, timings.draw, timings.present, timings.sleep =
            events, update, draw, present, sleep
        timings.frameReused = reused
    end
end

return FrameLoop
