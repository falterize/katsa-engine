local Game = require('source.game.runtime.game')
local Probe = {}
Probe.__index = Probe

function Probe.new(manager)
    io.stdout:setvbuf('no')
    local self = setmetatable(
        { manager = manager, frame = 0, rows = {}, sleep = 0, present = 0, pump = 0 },
        Probe
    )
    if os.getenv('KATSA_LOOP_PROFILE') == '1' then
        local profile = require('jit.profile')
        self.samples = {}
        profile.start('li1', function(thread, samples, state)
            local stack = profile.dumpstack(thread, 'pl', 3)
            local key = state .. ' ' .. stack
            self.samples[key] = (self.samples[key] or 0) + samples
        end)
    end
    local timerSleep, present, pump = katsa.timer.sleep, katsa.graphics.present, katsa.event.pump
    katsa.timer.sleep = function(duration)
        local started = katsa.timer.getTime()
        timerSleep(duration)
        self.sleep = (katsa.timer.getTime() - started) * 1000
    end
    katsa.graphics.present = function(...)
        local started = katsa.timer.getTime()
        present(...)
        self.present = (katsa.timer.getTime() - started) * 1000
    end
    katsa.event.pump = function(...)
        local started = katsa.timer.getTime()
        pump(...)
        self.pump = (katsa.timer.getTime() - started) * 1000
    end
    return self
end

function Probe:update(dt)
    self.frame = self.frame + 1
    if self.frame == 1 then
        self.scene = assert(
            self.manager:switch(Game.new, 'animationPhysicsLab', { physicsBackend = 'jolt' })
        )
        print('FRAME LOOP', katsa.graphics.getRendererInfo())
    elseif self.frame == 120 then
        self.scene.showStats = true
    elseif self.frame == 180 then
        for index, definition in ipairs(self.scene.statistics.panel.definitions) do
            if definition.id == 'fps' then
                self.scene.statistics.panel:select(index)
            end
        end
    end
    if self.frame > 240 then
        local manager = self.manager
        self.rows[#self.rows + 1] = table.concat({
            self.frame,
            dt * 1000,
            manager.frameGapMilliseconds or 0,
            self.sleep,
            self.present,
            self.pump,
            self.scene.updateMilliseconds or 0,
            self.scene.uiMilliseconds or 0,
            self.scene.physics.stats.updateMilliseconds or 0,
            collectgarbage('count'),
        }, ',')
    end
    if self.frame >= tonumber(os.getenv('KATSA_LOOP_FRAMES') or 2400) then
        local file = assert(io.open(assert(os.getenv('KATSA_LOOP_LOG')), 'w'))
        file:write(
            'frame,frame_ms,gap_ms,sleep_ms,present_ms,event_pump_ms,update_ms,ui_ms,physics_ms,lua_KB\n'
        )
        file:write(table.concat(self.rows, '\n'))
        file:close()
        print('FRAME LOOP COMPLETE', #self.rows)
        if self.samples then
            require('jit.profile').stop()
            local samples = {}
            for stack, count in pairs(self.samples) do
                samples[#samples + 1] = { stack, count }
            end
            table.sort(samples, function(a, b)
                return a[2] > b[2]
            end)
            for i = 1, math.min(35, #samples) do
                print('SAMPLE', samples[i][2], samples[i][1])
            end
        end
        katsa.event.quit()
    end
end

function Probe:draw() end

return Probe
