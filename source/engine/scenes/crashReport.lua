-- Shown on a phone when the previous run was killed: its log tail, a tap on the top half copies the
-- whole log to the clipboard, a tap on the bottom third continues to the normal start scene.
local Export = require('../debug.logExport')

local CrashReport = {}
CrashReport.__index = CrashReport

local TAIL = 22

function CrashReport.new(manager, continue)
    local text = katsa.filesystem.read('logs/previous.log') or '(no log was saved)'
    return setmetatable({
        manager = manager,
        settings = {},
        continue = continue,
        text = text,
        lines = Export.tail(text, TAIL),
    }, CrashReport)
end

function CrashReport:pointerpressed(id, x, y)
    local _, height = katsa.graphics.getDimensions()
    if y > height * 2 / 3 then
        self.continue()
    elseif id ~= 'mouse' then
        katsa.system.setClipboardText(self.text)
        self.copied = true
    end
end

function CrashReport:draw()
    local graphics = katsa.graphics
    local width, height = graphics.getDimensions()
    graphics.setColor(0.95, 0.8, 0.5)
    graphics.printf('The last run ended unexpectedly.', 0, 16, width, 'center')
    graphics.setColor(0.6, 0.6, 0.65)
    graphics.printf(
        self.copied and 'Log copied to the clipboard' or 'Tap here: copy the log',
        0,
        56,
        width,
        'center'
    )
    graphics.setColor(0.75, 0.75, 0.75)
    graphics.printf(self.lines, 16, 100, math.max(1, width - 32), 'left')
    graphics.setColor(0.3, 0.5, 0.3)
    graphics.rectangle('fill', 0, height * 2 / 3, width, height / 3)
    graphics.setColor(1, 1, 1)
    graphics.printf('Tap here: continue', 0, height * 5 / 6 - 8, width, 'center')
end

return CrashReport
