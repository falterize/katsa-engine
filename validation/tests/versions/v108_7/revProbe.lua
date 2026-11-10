local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests
function Tests.new(manager) local s = setmetatable(Previous.new(manager), Tests); s.frame=0; return s end
function Tests:update() end
function Tests:draw()
    self.frame = self.frame + 1
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load(); self.session = self.host.demo
        self.session:host('Tester', 47950 + math.floor(os.clock() * 100) % 9, { separate = false })
    end
    local ui = self.session.scene.ui
    local r0 = ui.revision
    self.host:update(1/60, 1/60); self.host:draw()
    if self.frame > 100 and self.frame <= 106 then print('REV frame', self.frame, 'delta', ui.revision - r0) end
    if self.frame == 110 then
        local counts, visible, total = {}, 0, 0
        local function walk(n, shown)
            total = total + 1
            local vis = shown and n.visible ~= false
            if vis then visible = visible + 1; counts[n.className or '?'] = (counts[n.className or '?'] or 0) + 1 end
            for _, c in ipairs(n.children or {}) do walk(c, vis) end
        end
        walk(ui.content or ui, true)
        local out = {}
        for k, v in pairs(counts) do out[#out + 1] = k .. '=' .. v end
        table.sort(out)
        print('UINODES total', total, 'visible', visible, table.concat(out, ' '))
        katsa.event.quit()
    end
end
return Tests
