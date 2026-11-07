-- Diagnostic: the Ramp goal editor and the scrolling curve graph for a -50..140 goal.
--   KATSA_SHOT=tmp/ramp xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.ramp
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

local function field(node, key)
    for _, f in ipairs(require('source.engine.editor.inspectors.properties').list(node)) do
        if f.key == key then
            return f
        end
    end
end

function Tests:draw()
    self.frame = (self.frame or 0) + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'shaderLab')
        self.host:load()
        local scene = self.host
        self.scene = scene
        local Sequence = require('source.engine.animation.sequence')
        local ramp = scene.world:create('Ramp', {
            mode = 'Animated',
            bindings = { position = Sequence.linear({ -50, 0, 0 }, { 140, 0, 0 }) },
            goals = { position = { 140, 0, 0 } },
        }, (scene.demo and scene.demo.body or scene.world.root))
        scene.workspace:toggle(true)
        scene.workspace:select(ramp)
        scene.workspace:openPopup(field(ramp, 'goals'))
        self.popup = scene.workspace.popup
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    if frame == 5 then
        katsa.graphics.captureScreenshot((os.getenv('KATSA_SHOT') or 'tmp/ramp') .. '/goals.png')
    elseif frame == 8 then
        require('source.engine.editor.curves.sequenceEditor').open(self.popup, 'position')
    elseif frame == 14 then
        katsa.graphics.captureScreenshot((os.getenv('KATSA_SHOT') or 'tmp/ramp') .. '/curve.png')
    elseif frame == 16 then
        -- Drag the last point (140) down by 60 px through the ScrollFrame.
        local graph, ui = self.popup.graph, self.host.ui
        ui:layout()
        local range = { graph.points[1].value[1], graph.points[2].value[1] }
        local x = (graph._x + graph._width - 14) * ui.scale + ui.offsetX
        local y = (graph._y + 40) * ui.scale + ui.offsetY
        local input = self.host.input
        local original = graph.pointer
        graph.pointer = function(g, u, phase, px, py, id)
            print('POINTER', phase, px, py)
            return original(g, u, phase, px, py, id)
        end
        local hit = ui:hit(x, y)
        for _, dx in ipairs({ 0, 20, 100, 300 }) do
            local h = ui:hit(x - dx, y)
            print('HITAT', dx, h and h.className)
        end
        print('HIT', hit and hit.className, hit and hit.name, x, y, graph._x, graph._y, graph._width, graph._height)
        input:press('curve', x, y)
        input:move('curve', x, y + 60, 0, 60)
        input:release('curve', x, y + 60)
        print('DRAG last point', range[2], '->', graph.points[2].value[1], 'height', graph._height)
    elseif frame == 18 then
        katsa.event.quit()
    end
end

return Tests
