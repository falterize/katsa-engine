-- A window resize re-applies the viewport at once, so the next (or a reused) frame is not cropped.
local State = require('source.katsa.graphics.state')

local Module = {}

function Module.run(self)
    local width, height = katsa.window.getSize()
    katsa.window.setSize(width + 120, height + 80)
    katsa.resize(katsa.graphics.getDimensions())
    local target = State.target
    local nowWidth, nowHeight = katsa.window.getSize()
    self:check(
        target.pw == nowWidth and target.ph == nowHeight,
        'The viewport follows a resized window before the next present'
    )
    katsa.window.setSize(width, height)
    katsa.resize(katsa.graphics.getDimensions())
end

return Module
