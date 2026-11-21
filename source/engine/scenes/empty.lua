-- What the window shows when no scene could be started (nothing to run, no start scene named, or a
-- scene that failed to load): a short message and the last log lines, so a phone (no console, no
-- F1) shows the reason too. A tap copies the whole log to the clipboard. The reason is also logged.
local Export = require('../debug.logExport')

local Empty = {}
Empty.__index = Empty

local MESSAGE = 'Could not start a scene.\nCheck the console for details.'
local TAIL = 10

function Empty.new(manager, options)
    local reason = options and options.reason or 'No scene to run.'
    katsa.log.write('warn', reason, 'scene')
    return setmetatable({ manager = manager, settings = {}, reason = reason }, Empty)
end

function Empty:pointerpressed(id)
    if id ~= 'mouse' then
        self.copied = Export.copy(katsa.log.entries())
    end
end

function Empty:draw()
    local graphics = katsa.graphics
    local width, height = graphics.getDimensions()
    graphics.setColor(0.85, 0.85, 0.85)
    graphics.printf(MESSAGE, 0, 24, width, 'center')
    graphics.setColor(0.6, 0.6, 0.65)
    graphics.printf(
        self.copied and ('Copied ' .. self.copied .. ' log entries') or 'Tap: copy the log',
        0,
        72,
        width,
        'center'
    )
    local lines = {}
    for _, entry in ipairs(katsa.log.tail(TAIL)) do
        lines[#lines + 1] = (entry.message:gsub('\n.*', ' ...'))
    end
    graphics.setColor(0.75, 0.75, 0.75)
    graphics.printf(table.concat(lines, '\n'), 24, 120, math.max(1, width - 48), 'left')
    graphics.setColor(1, 1, 1)
end

return Empty
