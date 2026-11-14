-- The ImGui plugin: native library, a rendered frame, input capture, the ImGuiLayer node.
local Module = {}

function Module.run(self)
    local ImGui = require('source.engine.plugins').require('imgui')
    if not ImGui.available() then
        print('SKIP imgui: ' .. tostring(ImGui.reason()))
        return
    end
    local gui = ImGui.new()
    self:check(gui ~= nil and gui.library.hash ~= nil, 'The ImGui library loads and creates a context')

    local width, height = 320, 240
    local canvas = katsa.graphics.newCanvas(width, height)
    local function frame()
        gui:frame(1 / 60, function(ig)
            ig.setNextWindowPos(10, 10)
            ig.setNextWindowSize(200, 120)
            if ig.begin('Probe') then
                ig.text('Hello katsa')
                ig.button('Press')
            end
            ig.finish()
        end)
        katsa.graphics.setCanvas(canvas)
        katsa.graphics.clear(0, 0, 0, 1)
        gui:draw()
        katsa.graphics.setCanvas()
    end
    frame()
    frame() -- the first frame uploads the font atlas
    local data = canvas:newImageData()
    local lit = 0
    for y = 0, height - 1, 4 do
        for x = 0, width - 1, 4 do
            local r, g, b = data:getPixel(x, y)
            if r + g + b > 0.05 then
                lit = lit + 1
            end
        end
    end
    self:check(lit > 200 and gui.renderer.stats.commands > 0, 'A frame renders windows into the canvas')

    gui:pointermoved('mouse', 50, 50)
    frame()
    self:check(gui:pointerpressed('mouse', 50, 50), 'A press over a window is taken by ImGui')
    gui:pointerreleased('mouse', 50, 50)
    gui:pointermoved('mouse', 300, 220)
    frame()
    self:check(not gui:pointerpressed('mouse', 300, 220), 'A press outside the windows passes through')
    gui:pointerreleased('mouse', 300, 220)

    local World3D = require('source.engine.world.world')
    local Resources = require('source.engine.core.resources')
    local world = World3D.new(Resources.new(require('source.game.data.manifest')))
    require('source.engine.plugins').activate(world, { 'imgui' })
    local layer = world:create('ImGuiLayer', { name = 'Gui', theme = 'Light', scale = 1.5 })
    local seen
    layer:connect('gui', function(ig)
        seen = ig
    end)
    gui:frame(1 / 60, function()
        layer:draw(gui)
    end)
    self:check(
        seen ~= nil and gui.C.igGetStyle().FontScaleMain == 1.5,
        'An ImGuiLayer node applies its theme and scale and emits the gui signal'
    )
    gui:release()
end

return Module
