-- `clip` keeps every descendant (nested ones too) inside the node, and with a UICorner inside the
-- rounded shape. Without `clip` a UICorner only shapes its own node.
local Node = require('source.engine.nodes')
local Resources = require('source.engine.core.resources')
local UI = require('source.engine.ui')

local Module = {}

local function render(clip, class)
    local ui = UI.new(64, 64, Resources.new(require('validation.tests.fixtures.manifest')))
    ui.parent = Node.new('World3D', {})
    local frame = ui:create(
        class or 'Frame',
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

-- A BillboardUI/SurfaceUI owner takes part like any container: `clip` ends content at the canvas,
-- a UICorner child rounds that cut. Reads the canvas after `refresh`.
local function renderPanel(class, clip)
    local World3D = require('source.engine.world.world')
    local settings = require('source.runtime.settings').create()
    local resources = Resources.new(require('validation.tests.fixtures.manifest'))
    local world = World3D.new(resources, settings)
    local camera = world:addCamera()
    camera:update(640, 360)
    local support = world:create('Mesh3D', {
        name = 'Support',
        position = { 0, 0, 100 },
        size = { 20, 40, 10 },
    })
    local panel = world:create(class, {
        name = 'Panel',
        adornee = support,
        size = { 0, 64, 0, 64 },
        canvasSize = { 0, 64, 0, 64 },
        clip = clip,
    })
    local holder = panel.ui:create('Frame', { width = 64, height = 64 }, panel)
    panel.ui:create(
        'ImageRect',
        { x = -14, y = -14, width = 92, height = 92, image = 'white', tint = { 0, 1, 0, 1 } },
        holder
    )
    panel.ui:create('UICorner', { cornerRadius = 10 }, panel)
    panel:update(world, camera)
    panel:refresh()
    local pixels = panel.canvas:newImageData()
    local scale = panel.canvasDensity
    local function green(x, y)
        local r, g, b, a = pixels:getPixel(
            math.floor((x - panel.bounds[1]) * scale),
            math.floor((y - panel.bounds[2]) * scale)
        )
        return g > 0.9 and a > 0.9
    end
    local result = { center = green(32, 32), corner = green(1, 1), mid = green(32, 2) }
    pixels:release()
    return result
end

function Module.run(self)
    local on = render(true)
    self:check(
        on.center and not on.outside and not on.corner,
        'clip on: nested descendants stop at the rounded shape'
    )
    for _, class in ipairs({ 'ImageRect', 'Button', 'CanvasGroup' }) do
        local r = render(true, class)
        self:check(
            r.center and not r.outside and not r.corner,
            class .. ' clip: nested descendants stop at the rounded shape'
        )
    end
    local off = render(false)
    self:check(
        off.center and off.outside and off.corner,
        'clip off: a UICorner does not cut its children'
    )
    for _, class in ipairs({ 'BillboardUI', 'SurfaceUI' }) do
        local clipped = renderPanel(class, true)
        self:check(
            clipped.center and clipped.mid and not clipped.corner,
            class .. ' clip: content ends at the canvas and the UICorner rounds it'
        )
    end
    local free = renderPanel('BillboardUI', false)
    self:check(free.corner, 'BillboardUI without clip: content is not cut by the corner')
end

return Module
