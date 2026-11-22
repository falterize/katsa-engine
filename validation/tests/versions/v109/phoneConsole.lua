-- The phone console: a three-finger gesture, the copy button and the tap-to-copy failure screen.
local Gesture = require('source.engine.debug.touchGesture')
local Export = require('source.engine.debug.logExport')
local Empty = require('source.engine.scenes.empty')

local Module = {}

function Module.run(self)
    local gesture = Gesture.new(3)
    self:check(not gesture:press('mouse'), 'The mouse never counts as a finger')
    gesture:press(1)
    gesture:press(2)
    self:check(gesture:press(3), 'The third finger opens the console')
    self:check(not gesture:press(4), 'The gesture fires once per touch')
    for id = 1, 4 do
        gesture:release(id)
    end
    gesture:press(5)
    gesture:press(6)
    self:check(gesture:press(7), 'The gesture can fire again after all fingers lift')

    local copied
    local original = katsa.system.setClipboardText
    katsa.system.setClipboardText = function(text)
        copied = text
    end
    katsa.log.write('warn', 'phone console probe', 'test')
    local count = Export.copy(katsa.log.entries())
    self:check(count > 0 and copied:find('phone console probe', 1, true), 'Copy puts the log on the clipboard')

    copied = nil
    local empty = Empty.new({}, { reason = 'No scene to run.' })
    empty:pointerpressed('mouse')
    self:check(copied == nil, 'A mouse click does not copy on the failure screen')
    empty:pointerpressed(1)
    self:check(copied and copied:find('No scene to run.', 1, true), 'A tap copies the log with the failure reason')
    katsa.system.setClipboardText = original

    local Session = require('source.engine.debug.session')
    katsa.filesystem.createDirectory('logs')
    Session.mark('probe', true)
    self:check(katsa.filesystem.getInfo('logs/probe-running') ~= nil, 'A running session leaves a marker')
    Session.mark('probe', false)
    self:check(katsa.filesystem.getInfo('logs/probe-running') == nil, 'A finished session removes it')
    self:check(
        Export.tail('a\nb\nc\nd', 2) == 'c\nd' and Export.tail('', 3) == '',
        'The log tail keeps the last lines'
    )
    local continued = 0
    katsa.filesystem.write(
        'logs/previous.log',
        '2026-11-22T12:16:20Z [log] touch down 0 at 657,493\nstack traceback:\n\tsource/a.lua:3: in function x\n'
            .. string.rep('long ', 40)
            .. '\n'
    )
    local report = require('source.engine.scenes.crashReport').new({}, function()
        continued = continued + 1
    end)
    local drawn, drawMessage = pcall(report.draw, report)
    self:check(drawn, 'The crash report draws a real log: ' .. tostring(drawMessage))
    local _, height = katsa.graphics.getDimensions()
    report:pointerpressed(1, 10, height * 0.9)
    self:check(continued == 1, 'The bottom of the crash report continues to the scene')
    local copiedReport
    katsa.system.setClipboardText = function(text)
        copiedReport = text
    end
    report:pointerpressed(1, 10, 10)
    katsa.system.setClipboardText = original
    self:check(copiedReport ~= nil and continued == 1, 'The top of the crash report copies the log')

    local Game = require('source.runtime.game')
    local scene = assert(self.manager:switch(Game.new, 'physics'))
    for id = 1, 3 do
        scene:pointerpressed(id, 10 * id, 10)
    end
    self:check(scene.console.visible, 'Three fingers open the on-screen console in a scene')
    for id = 1, 3 do
        scene:pointerreleased(id, 10 * id, 10)
    end
    for id = 4, 6 do
        scene:pointerpressed(id, 10 * id, 10)
    end
    self:check(not scene.console.visible, 'Three fingers again close it')

    -- "Continue" runs inside an input handler, where a scene switch is only queued.
    local manager = self.manager
    assert(manager:switch(function(owner)
        return require('source.engine.scenes.crashReport').new(owner, function()
            manager:switch(Game.new, 'physics')
        end)
    end))
    local _, screenHeight = katsa.graphics.getDimensions()
    manager:dispatch('pointerpressed', 1, 10, screenHeight * 0.9)
    manager:update(0.01)
    self:check(manager.stack[1].runtime == 'game', 'Continue on the crash report starts the scene')
end

return Module
