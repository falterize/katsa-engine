local Schema = require('source.engine.editor.inspectors.schema')
local Order = require('source.engine.ui.layout.order')
local Plane = require('source.engine.ui.spatial.plane')
local Tests = {}

local function has(target, key)
    for _, candidate in ipairs(Schema.keys(target, {})) do
        if candidate == key then
            return true
        end
    end
    return false
end

function Tests.run(tester)
    local world, ui, physics, body, release = tester:environment()
    ui.width, ui.height, ui.scale, ui.offsetX, ui.offsetY = 256, 256, 1, 0, 0
    tester:check(
        not has(world.root, 'position')
            and not has(world.root, 'rotation')
            and not has(world.root, 'scale'),
        'World3D has no editable transform settings'
    )
    tester:check(
        has(ui, 'transparency') and ui.transparency == 0,
        'World2D exposes zero-default transparency'
    )
    local item = body(128, 128, 'Static')
    local collider = ui:create('Collider2D', { size = { 40, 20 }, position = { 10, 0 } }, item)
    local visual = world:create('Button', {
        name = 'Visual',
        size = { 1, 0, 1, 0 },
        backgroundColor = { 1, 0, 0 },
        text = '',
    }, collider)
    local spatial = ui:create('Node2D', {})
    tester:check(
        not has(spatial, 'layers') and not has(spatial, 'color') and not has(spatial, 'zIndex'),
        'Node2D does not expose rendering material or bitmask fields'
    )
    tester:check(
        not has(collider, 'color') and not has(collider, 'transparency'),
        'Collider2D exposes geometry rather than a material'
    )
    tester:check(visual.parent == collider, 'Visual widgets can belong directly to Collider2D')
    ui:layout()
    tester:check(
        visual._width == 40 and visual._height == 20 and visual._x == 0,
        'UDim2 fill resolves against the collider dimensions'
    )
    local original = ui:getChildren()
    local a = ui:create('Frame', { size = { 0, 20, 0, 20 }, zIndex = 20 }, ui.content)
    local b = ui:create('Button', { size = { 0, 20, 0, 20 }, zIndex = -1 }, ui.content)
    local stable = true
    for i = 1, 100 do
        b.zIndex = i % 2 == 0 and 30 or -1
        ui:invalidate()
        ui:layout()
        for j, node in ipairs(original) do
            stable = stable and ui.children[j] == node
        end
    end
    tester:check(stable, 'Repeated layout preserves spatial tree order')
    tester:check(
        ui.content.children[1] == a and ui.content.children[2] == b,
        'ZIndex changes do not reorder authored widget children'
    )
    tester:check(
        Order.get(ui.content.children)[1] == a and ui:hit(10, 10) == b,
        'Rendering and hit testing still honor ZIndex'
    )
    a:destroy()
    b:destroy()
    item.rotation = 90
    ui:update(0)
    local camera = ui:create('Camera2D', {
        position = { 128, 128 },
        rotation = 35,
        referenceHeight = 256,
        zoom = 1.5,
    })
    local x, y = Plane.pose(collider)
    local sx, sy = ui:worldToScreen2D(x, y)
    tester:check(
        ui:hit(sx, sy) == visual,
        'Rotated body and camera share the visual hit-test transform'
    )
    tester:check(
        ui:blocksWorldClick(sx, sy),
        'Spatial visual UI blocks clicks through to 3D content'
    )
    collider.size = { 80, 30 }
    ui:layout()
    tester:check(
        visual._width == 80 and visual._height == 30,
        'Editing collider size updates relative widget dimensions'
    )
    local slider = ui:create('Slider', { size = { 1, 0, 1, 0 } }, collider)
    local px, py, angle = Plane.pose(collider)
    local dx = collider.size[1] / 2 - 12
    sx, sy = ui:worldToScreen2D(px + dx * math.cos(angle), py + dx * math.sin(angle))
    ui:pointer(slider, 'press', sx, sy, 'test')
    tester:check(slider.value > 0.99, 'Spatial slider drags use local coordinates')
    slider:destroy()
    local canvas = love.graphics.newCanvas(256, 256, { dpiscale = 1 })
    local function render(alpha)
        ui.transparency = alpha
        love.graphics.push('all')
        love.graphics.setCanvas({ canvas, stencil = true })
        love.graphics.origin()
        love.graphics.clear(0, 0, 0, 0, 0)
        ui:draw()
        love.graphics.pop()
        local data = canvas:newImageData()
        local r, g, b, a = data:getPixel(128, 143)
        data:release()
        return r, g, b, a
    end
    camera.rotation, camera.zoom = 0, 1
    local r, _, _, alpha = render(0)
    tester:check(r > 0.95 and alpha > 0.95, 'Collider-owned UI renders at its physical pose')
    local cached = collider._uiSurface.canvas
    item.position[1] = item.position[1] + 1
    ui:update(0)
    render(0)
    tester:check(
        collider._uiSurface.canvas == cached,
        'Moving a rigid body reuses its local visual canvas'
    )
    local _, _, _, half = render(0.5)
    tester:check(
        math.abs(half - 0.5) < 0.02,
        'World2D transparency composites physical visuals with correct alpha'
    )
    local _, _, _, hidden = render(1)
    tester:check(
        hidden == 0 and ui:hit(128, 143) == nil,
        'Fully transparent World2D neither renders nor captures pointers'
    )
    ui.transparency = 0
    collider:destroy()
    tester:check(
        visual.destroyed and collider._uiSurface.canvas == nil,
        'Destroying a collider releases its visual descendants and owned canvas'
    )
    physics.debug.enabled = false
    local _, _, _, empty = render(0)
    tester:check(empty == 0, 'Physics bodies without visual descendants do not draw solid shapes')
    canvas:release()
    release()
end

return Tests
