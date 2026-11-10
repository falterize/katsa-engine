local Viewport = {}

function Viewport.run(tests, ui, density)
    local frame = ui:create('ViewportFrame', {
        position = { 0, 10, 0, 10 },
        size = { 0, 300, 0, 160 },
    }, ui.content)
    local root = ui:create('World3D', { name = 'TextViewport' }, frame)
    root.currentCamera = nil
    local inner = root:create('World2D', { name = 'ViewportOverlay' })
    local clicks = 0
    local scroll = inner:scroll({
        size = { 0, 250, 0, 140 },
        scrollingDirection = 'XY',
        canvasSize = { 0, 600, 0, 500 },
        scrollBarThickness = 12,
    }, inner.content)
    do
        local node = inner:button({
            size = { 0, 600, 0, 500 },
            text = 'Viewport text',
            fontSize = 13,
        }, scroll)
        node:connect('press', function()
            clicks = clicks + 1
        end)
    end
    local canvas = katsa.graphics.newCanvas(480 * density, 320 * density, { dpiscale = 1 })
    local function render()
        katsa.graphics.push('all')
        katsa.graphics.setCanvas({ canvas, stencil = true })
        katsa.graphics.origin()
        katsa.graphics.clear(0, 0, 0, 0, 0)
        ui:draw()
        katsa.graphics.pop()
    end
    render()
    tests:check(
        inner.density == density
            and root._world.overlayCanvas:getPixelWidth() == math.ceil(300 * density),
        'Viewport overlay follows the physical target density'
    )
    inner:scrollBy(scroll, 100, 100)
    render()
    local x, y = 80 * density, 80 * density
    ui:pointer(frame, 'press', x, y, 'viewport')
    ui:pointer(frame, 'move', x + 20 * density, y + 20 * density, 'viewport')
    ui:pointer(frame, 'release', x + 20 * density, y + 20 * density, 'viewport')
    tests:check(
        scroll.scrollX < 100 and scroll.scrollY < 100 and clicks == 0,
        'Viewport content drag uses shared capture without accidental clicks'
    )
    inner:scrollBy(scroll, 100 - scroll.scrollY, 100 - scroll.scrollX)
    render()
    local bar = require('source.engine.ui.scrolling.scrollBar').geometry(scroll, false)
    x, y =
        (frame._x + bar.x + bar.width * 0.5) * density,
        (frame._y + bar.y + bar.height * 0.5) * density
    ui:pointer(frame, 'press', x, y, 'thumb')
    ui:pointer(frame, 'move', x, y + 10 * density, 'thumb')
    ui:pointer(frame, 'release', x, y + 10 * density, 'thumb')
    tests:check(
        scroll.scrollY > 100 and math.abs(scroll.scrollX - 100) < 0.001,
        'Viewport scrollbar follows the pointer on the selected axis'
    )
    canvas:release()
    frame:destroy()
end

return Viewport
