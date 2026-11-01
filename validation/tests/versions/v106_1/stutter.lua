local Game = require('source.game.runtime.game')
local Probe = {}
Probe.__index = Probe

function Probe.new(manager)
    io.stdout:setvbuf('no')
    if os.getenv('KATSA_STUTTER_TUNE') == '1' then
        require('jit.opt').start('maxtrace=8000', 'maxmcode=8192')
    end
    katsa.errorhandler = function(message)
        print('FAILED STUTTER ' .. tostring(message))
        os.exit(1)
    end
    katsa.window.setMode(1920, 1080, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, Probe)
end

function Probe:update() end

function Probe:draw()
    if self.done then
        return
    end
    self.done = true
    local scene =
        assert(self.manager:switch(Game.new, 'animationPhysicsLab', { physicsBackend = 'jolt' }))
    local original = katsa.graphics.newText
    local created = 0
    katsa.graphics.newText = function(...)
        created = created + 1
        return original(...)
    end
    local records = {}
    local events = {}
    if jit and os.getenv('KATSA_STUTTER_JIT') == '1' then
        jit.attach(function(what, trace, func, pc, reason)
            local key = what == 'abort' and what .. ':' .. tostring(reason) or what
            events[key] = (events[key] or 0) + 1
        end, 'trace')
    end
    local uiDraw, uiMilliseconds = scene.ui.draw, 0
    scene.ui.draw = function(ui, ...)
        local start = katsa.timer.getTime()
        uiDraw(ui, ...)
        uiMilliseconds = (katsa.timer.getTime() - start) * 1000
    end
    print('frame,mode,total_ms,update_ms,draw_ms,present_ms,physics_ms,KB_delta,new_text,ui_ms')
    for frame = 1, tonumber(os.getenv('KATSA_STUTTER_FRAMES') or 900) do
        katsa.event.pump()
        if frame == 121 then
            scene.showStats = true
        end
        if frame == 181 then
            for index, definition in ipairs(scene.statistics.panel.definitions) do
                if definition.id == 'fps' then
                    scene.statistics.panel:select(index)
                end
            end
        end
        local memory = collectgarbage('count')
        created = 0
        local begin = katsa.timer.getTime()
        self.manager:update(1 / 60)
        local updated = katsa.timer.getTime()
        self.manager:draw()
        katsa.graphics.flushBatch()
        local drawn = katsa.timer.getTime()
        katsa.graphics.present()
        local finish = katsa.timer.getTime()
        local row = {
            frame,
            frame < 121 and 'closed' or frame < 181 and 'list' or 'chart',
            (finish - begin) * 1000,
            (updated - begin) * 1000,
            (drawn - updated) * 1000,
            (finish - drawn) * 1000,
            scene.physics.stats.updateMilliseconds or 0,
            collectgarbage('count') - memory,
            created,
            uiMilliseconds,
        }
        records[#records + 1] = row
        if frame == 121 or frame == 181 or row[3] > 33 then
            print(unpack(row))
        end
    end
    katsa.graphics.newText = original
    local path = os.getenv('KATSA_STUTTER_LOG')
    if path then
        local file = assert(io.open(path, 'w'))
        file:write(
            'frame,mode,total_ms,update_ms,draw_ms,present_ms,physics_ms,KB_delta,new_text,ui_ms\n'
        )
        for _, row in ipairs(records) do
            file:write(table.concat(row, ','), '\n')
        end
        file:close()
    end
    for _, mode in ipairs({ 'closed', 'list', 'chart' }) do
        local values, sum = {}, 0
        for _, row in ipairs(records) do
            if row[2] == mode then
                values[#values + 1] = row[3]
                sum = sum + row[3]
            end
        end
        if #values > 0 then
            table.sort(values)
            print(
                'SUMMARY',
                mode,
                'mean/p95/p99/max',
                sum / #values,
                values[math.ceil(#values * 0.95)],
                values[math.ceil(#values * 0.99)],
                values[#values]
            )
        end
    end
    print('STUTTER PROFILE COMPLETE')
    print('JIT FLUSHES', events.flush or 0)
    for key, value in pairs(events) do
        print('JIT EVENT', key, value)
    end
    katsa.event.quit()
end

return Probe
