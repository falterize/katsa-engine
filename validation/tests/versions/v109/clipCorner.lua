-- `clip` keeps every descendant (nested ones too) inside the node, and with a UICorner inside the
-- rounded shape.
local Node = require('source.engine.nodes')
local Resources = require('source.engine.core.resources')
local UI = require('source.engine.ui')

local Module = {}

local function render(clip)
    local ui = UI.new(64, 64, Resources.new(require('validation.tests.fixtures.manifest')))
    ui.parent = Node.new('World3D', {})
    local frame = ui:create(
        'Frame',
        { x = 20, y = 20, width = 24, height = 24, color = { 1, 0, 0, 1 }, clip = clip },
        ui.content
    )
    -- The child covers the frame and overflows it by 14 px on every side.
    local holder = ui:create('Frame', { width = 24, height = 24, color = { 0, 0, 0, 0 } }, frame)
    ui:create(
        'ImageRect',
        { x = -14, y = -14, width = 52, height = 52, image = 'white', tint = { 0, 1, 0, 1 } },
        holder
    )
    ui:create('UICorner', { cornerRadius = 10 }, frame)
    local canvas = katsa.graphics.newCanvas(64, 64)
    katsa.graphics.push('all')
    katsa.graphics.setCanvas({ canvas, stencil = true })
    katsa.graphics.clear(0, 0, 1, 1)
    ui:draw()
    katsa.graphics.setCanvas()
    katsa.graphics.pop()
    local pixels = canvas:newImageData()
    local function green(x, y)
        local r, g, b = pixels:getPixel(x, y)
        return g > 0.9 and r < 0.1 and b < 0.1
    end
    local result = {
        outside = green(10, 10), -- beyond the frame rectangle
        corner = green(21, 21), -- inside the rectangle, outside the rounded corner
        center = green(32, 32),
    }
    pixels:release()
    canvas:release()
    ui:release()
    return result
end

function Module.run(self)
    local on = render(true)
    self:check(on.center and not on.outside and not on.corner, 'clip on: nested descendants stop at the rounded shape')
end

return Module
