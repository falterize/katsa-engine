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
end

return Module
