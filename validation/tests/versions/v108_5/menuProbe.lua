-- Diagnostic: frame cost of the menu scene (idle and while its lists scroll), per profiler stage.
-- Run: xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.5.menu   (KATSA_PROF=<file> adds jit.p)
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    self.buckets = { idle = { update = 0, draw = 0, n = 0 }, scroll = { update = 0, draw = 0, n = 0 } }
    return self
end

function Tests:update() end

local function findScroll(node, found)
    found = found or {}
    if node.className == 'ScrollFrame' or (node.isA and node:isA('ScrollFrame')) then
        found[#found + 1] = node
    end
    for _, child in ipairs(node.children or {}) do
        findScroll(child, found)
    end
    return found
end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'menu')
        self.host:load()
        self.manager.profiler:startRecording({ scene = 'menu' })
    end
    local host = self.host
    if not host then
        return
    end
    local scroll = frame >= 200 and frame < 300
    if scroll and frame % 1 == 0 then
        local ui = host.scene and host.scene.state and host.scene.state.ui or host.ui
        for _, frameNode in ipairs(ui and findScroll(ui) or {}) do
            frameNode.scrollY = (frameNode.scrollY or 0) + (frame % 2 == 0 and 7 or -5)
            ui:invalidate()
        end
    end
    local t0 = os.clock()
    host:update(1 / 60, 1 / 60)
    local t1 = os.clock()
    host:draw()
    local t2 = os.clock()
    local bucket = frame >= 100 and frame < 200 and self.buckets.idle or scroll and self.buckets.scroll
    if bucket then
        bucket.update, bucket.draw, bucket.n = bucket.update + (t1 - t0), bucket.draw + (t2 - t1), bucket.n + 1
    end
    if frame == (os.getenv('KATSA_PHASE') == 'idle' and 100 or 200) and os.getenv('KATSA_PROF') then
        require('jit.p').start('Fl1i1', os.getenv('KATSA_PROF'))
    end
    if frame == (os.getenv('KATSA_PHASE') == 'idle' and 199 or 299) and os.getenv('KATSA_PROF') then
        require('jit.p').stop()
    end
    if frame == 30 and os.getenv('KATSA_SHOT') then
        katsa.graphics.captureScreenshot(os.getenv('KATSA_SHOT'))
    end
    if frame == 150 or frame == 250 then
        local st = katsa.graphics.getStats()
        print(('GFX f%d drawcalls=%s batched=%s canvasswitches=%s shaderswitches=%s'):format(frame, tostring(st.drawcalls), tostring(st.drawcallsbatched), tostring(st.canvasswitches), tostring(st.shaderswitches)))
    end
    if frame == 300 then
        for name, b in pairs(self.buckets) do
            print(('PROBE %-7s update %.2f ms  draw %.2f ms'):format(name, b.update / b.n * 1000, b.draw / b.n * 1000))
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
