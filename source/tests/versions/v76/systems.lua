-- CPU system audit. Submission timings include driver calls, not GPU completion.
local T = {}
T.__index = T

function T.new(manager)
    love.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    for _, zone in ipairs({
        'combined',
        'animationPhysicsLab',
        'modelLab',
        'particles',
        'viewports',
        'uiGallery',
    }) do
        local s = self.manager:switch(require('source.game.runtime.game').new, zone)
        s.showStats = false

        local function measure(label, callback)
            for _ = 1, 12 do
                callback()
            end
            local rounds = {}
            for round = 1, 3 do
                collectgarbage('collect')
                local memory = collectgarbage('count')
                local start = love.timer.getTime()
                for _ = 1, 60 do
                    callback()
                end
                rounds[round] = (love.timer.getTime() - start) * 1000 / 60
                print('MEMORY', zone, label, round, collectgarbage('count') - memory)
            end
            table.sort(rounds)
            print(
                'SYSTEM',
                zone,
                label,
                string.format('%.4f', rounds[2]),
                'ms median; range',
                rounds[1],
                rounds[3]
            )
        end
        measure('update', function()
            s:update(1 / 60)
        end)
        print(
            'COUNTS',
            zone,
            #s.world.objects,
            #(s.world.animators or {}),
            #(s.physics and s.physics.bodies or {})
        )
        if s.physics then
            print('SOLVER', zone, s.physics.stats.solverMilliseconds)
        end
        measure('UI submit', function()
            s.ui:draw()
        end)
        s.workspace:toggle(true)
        measure('Explorer update', function()
            s.workspace:update(1 / 60)
        end)
        measure('Explorer UI submit', function()
            s.ui:draw()
        end)
        s.workspace:toggle(false)
    end
    love.event.quit()
end

return T
