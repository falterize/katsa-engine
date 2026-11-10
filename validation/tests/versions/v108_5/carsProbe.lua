-- Diagnostic: compares the frame cost of multiplayerCars on foot and inside the car.
-- Run with KATSA_PROF=<file> to also write a LuaJIT sampling profile of the in-car frames.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame, self.walk, self.drive = 0, { update = 0, draw = 0, n = 0 }, { update = 0, draw = 0, n = 0 }
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self.manager.profiler:startRecording({ scene = 'multiplayerCars' })
        self.session:host('Tester', 47980 + math.floor(os.clock() * 100) % 9)
    end
    local host, session = self.host, self.session
    if not host then
        return
    end
    local t0 = os.clock()
    host:update(1 / 60, 1 / 60)
    local t1 = os.clock()
    host:draw()
    local t2 = os.clock()
    local bucket = frame >= 100 and frame < 200 and self.walk or frame >= 230 and frame < 330 and self.drive
    if bucket then
        bucket.update, bucket.draw, bucket.n = bucket.update + (t1 - t0), bucket.draw + (t2 - t1), bucket.n + 1
    end
    if frame == 190 or frame == 300 then
        local r = host.world._activeRenderer
        local out = {}
        for k, v in pairs(r and r.stats or {}) do
            if type(v) == 'number' then out[#out + 1] = k .. '=' .. v end
        end
        table.sort(out)
        local sh = r and r.shadows
        print(('RSTATS f%d %s | shadow updated=%s casters=%s tris=%s'):format(frame, table.concat(out, ' '), tostring(sh and sh.updatedFaces), tostring(sh and sh.casterSubmissions), tostring(sh and sh.triangles)))
    end
    if frame == 201 then
        session.server.game.bot.sightRadius = 0
        session:changeCar()
    elseif frame == 215 then
        print('SEAT', session.client:getCar() ~= nil)
    end
    if frame == (os.getenv('KATSA_PHASE') == 'walk' and 100 or 232) then
        if os.getenv('KATSA_PROF') then
            require('jit.p').start('Fl1i1', os.getenv('KATSA_PROF'))
        end
    end
    if frame == (os.getenv('KATSA_PHASE') == 'walk' and 190 or 330) and os.getenv('KATSA_PROF') then
        require('jit.p').stop()
    end
    if frame == 330 then
        for _, row in ipairs({ { 'on foot', self.walk }, { 'in car', self.drive } }) do
            local b = row[2]
            print(('PROBE %-8s update %.2f ms  draw %.2f ms'):format(row[1], b.update / b.n * 1000, b.draw / b.n * 1000))
        end
        local rows = self.manager.profiler.recording.rows
        local function mean(from, to)
            local sums, count = {}, 0
            for i = from, to do
                local row = rows[i]
                if row then
                    count = count + 1
                    sums.frame = (sums.frame or 0) + row.ms
                    sums.lua = (sums.lua or 0) + row.lua
                    for name, value in pairs(row.stages) do
                        sums[name] = (sums[name] or 0) + (type(value) == 'table' and value.ms or value)
                    end
                end
            end
            return sums, count
        end
        local walk, n1 = mean(100, 199)
        local drive, n2 = mean(235, 325)
        local names = {}
        for name in pairs(drive) do names[#names + 1] = name end
        table.sort(names, function(x, y) return drive[x] > drive[y] end)
        for _, name in ipairs(names) do
            print(('CMP %-32s walk %7.2f ms   car %7.2f ms'):format(tostring(name), (walk[name] or 0) / n1, drive[name] / n2))
        end
        local summary = self.manager.profiler:summary()
        for _, stage in ipairs(summary.stages) do
            local fields = {}
            for k, v in pairs(stage) do
                fields[#fields + 1] = k .. '=' .. (type(v) == 'number' and ('%.3f'):format(v) or tostring(v))
            end
            table.sort(fields)
            print('STAGE ' .. table.concat(fields, ' '))
        end
        print('PASSED probe')
        katsa.event.quit()
    end
end

return Tests
