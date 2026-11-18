-- Diagnostic: frame cost of the levelEditor scene per profiler stage (idle, then with a selection).
-- Run: xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.9.editor
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    self.buckets = { idle = { update = 0, draw = 0, n = 0 }, selected = { update = 0, draw = 0, n = 0 } }
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('game.runtime.application').new(self.manager, 'levelEditor')
        self.host:load()
        self.manager.profiler:startRecording({ scene = 'levelEditor' })
    end
    local host = self.host
    if not host then
        return
    end
    if frame == 150 then
        local editor = host.state or host.package.instance
        local first = editor and editor.level and editor.level.children[1]
        if first then
            editor.selection:set({ first })
        end
    end
    if frame == 10 and os.getenv('KATSA_NOSHADOW') then (host.state or host.package.instance).world.environment.shadows.enabled = false end
    if frame == 10 and os.getenv('KATSA_HIDE') then
        local editor = host.state or host.package.instance
        for name in os.getenv('KATSA_HIDE'):gmatch('[^,]+') do
            if name == 'viewport' then
                editor.viewport.visible = false
            else
                local node = editor.ui:find(name)
                if node then node.visible = false end
            end
        end
    end
    if frame == 10 and os.getenv('KATSA_MAIN') then
        local editor = host.state or host.package.instance
        local world = editor.scene.world
        local e = world.environment
        print('MAINWORLD', tostring(world), e.sky.enabled, e.shadows.enabled, e.render.renderDensity, e.glow.enabled, e.ssao.enabled)
        e.sky.enabled = false
        e.shadows.enabled = false
        if os.getenv('KATSA_MAIN') == 'density' then e.render.renderDensity = 0.5 end
    end
    if frame == 10 and os.getenv('KATSA_EDW') then
        local e = (host.state or host.package.instance).world.environment
        for name in os.getenv('KATSA_EDW'):gmatch('[^,]+') do
            if name == 'fog' then e.fog.enabled = false
            elseif name == 'msaa' then e.render.msaa = 0
            elseif name == 'prepass' then e.render.depthPrepass = false
            elseif name == 'sky' then e.sky.enabled = false
            elseif name == 'density' then e.render.renderDensity = 0.5 end
        end
    end
    local t0 = os.clock()
    host:update(1 / 60, 1 / 60)
    local t1 = os.clock()
    host:draw()
    local t2 = os.clock()
    if frame >= 100 and (t1 - t0) > 0.008 then print(('SPIKE frame %d update %.1f ms'):format(frame, (t1 - t0) * 1000)) end
    local bucket = frame >= 60 and frame < 150 and self.buckets.idle or frame >= 160 and frame < 250 and self.buckets.selected
    if bucket then
        bucket.update, bucket.draw, bucket.n = bucket.update + (t1 - t0), bucket.draw + (t2 - t1), bucket.n + 1
    end
    if frame == 250 then
        for name, b in pairs(self.buckets) do
            print(('PROBE %-8s update %.2f ms  draw %.2f ms'):format(name, b.update / b.n * 1000, b.draw / b.n * 1000))
        end
        local summary = self.manager.profiler:summary()
        for _, stage in ipairs(summary.stages) do
            local f = {} for k, v in pairs(stage) do f[#f + 1] = k .. '=' .. (type(v) == 'number' and ('%.2f'):format(v) or tostring(v)) end table.sort(f) print('STAGE ' .. table.concat(f, ' '))
        end
        print('PASSED probe')
        katsa.event.quit()
    end
end

return Tests
