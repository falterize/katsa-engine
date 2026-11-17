-- The Debug, Profiler and Console tool windows of the ImGui plugin, driven through a real scene.
local Application = require('game.runtime.application')

local Module = {}

function Module.run(self)
    local ImGui = require('source.engine.plugins').require('imgui')
    if not ImGui.available() then
        print('SKIP imguiTools: ' .. tostring(ImGui.reason()))
        return
    end
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local host = scene:module('editor').imgui
    self:check(host ~= nil, 'A scene attaches the ImGui host')

    scene:keypressed('f4')
    scene:keypressed('f1')
    self:check(
        host.open.debug and host.open.console,
        'F4 opens the Debug window and F1 the Console'
    )
    host:toggle('profiler')
    katsa.log.warn('Тест консоли: привет')
    for _ = 1, 3 do
        host:frame(1 / 60)
    end
    local lines = host.state.console.shown
    self:check(
        #lines > 0 and lines[#lines].text:find('привет', 1, true) ~= nil,
        'The Console lists new log lines, non-Latin text included'
    )
    host.state.console.filter = 'привет'
    host:frame(1 / 60)
    self:check(#host.state.console.shown >= 1 and #host.state.console.shown <= 3, 'The Console text filter narrows the lines')

    -- A window that grows replaces the draw mesh while the previous one was the last bound: drawing
    -- the larger frame must not read a stale element buffer (it used to crash the process).
    host:close('debug')
    host:close('profiler')
    host:close('console')
    local width, height = katsa.graphics.getDimensions()
    local canvas = katsa.graphics.newCanvas(width, height, { dpiscale = 1 })
    local function drawFrame()
        host:frame(1 / 60)
        katsa.graphics.setCanvas(canvas)
        host:draw()
        katsa.graphics.setCanvas()
    end
    scene.showStats = true
    drawFrame()
    host:toggle('debug')
    host:toggle('console')
    drawFrame()
    drawFrame()
    self:check(host.backend.renderer.stats.vertices > 400, 'A growing ImGui frame draws after its mesh was replaced')
    host:close('console')

    -- Every Debug tab draws (a tab is built only while it is selected).
    for _, title in ipairs({ '3D Physics', 'Rendering', 'Directions', 'Diagnostics', '2D Physics' }) do
        host.state.debug.showTab = title
        host:frame(1 / 60)
        host:frame(1 / 60)
    end
    self:check(host.open.debug, 'All Debug tabs and the Profiler draw without errors')
    scene:release()

    -- Scenes with a 3D and a 2D physics world fill the physics tabs.
    for _, name in ipairs({ 'physics', 'physics2D' }) do
        local physical = Application.new(self.manager, name)
        physical:load()
        local physicalHost = physical:module('editor').imgui
        physicalHost:toggle('debug')
        physicalHost:toggle('profiler')
        for _, title in ipairs({ '3D Physics', '2D Physics', 'Rendering' }) do
            physicalHost.state.debug.showTab = title
            physicalHost:frame(1 / 60)
            physicalHost:frame(1 / 60)
        end
        self:check(physicalHost.open.debug, 'The Debug tabs draw in the ' .. name .. ' scene')
        physical:release()
    end
end

return Module
