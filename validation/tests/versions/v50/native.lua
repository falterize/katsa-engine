-- Native pixel and semantic regressions for v50, independent of demonstration placement.
return function(test)
    local UI = require('source.engine.ui')
    local Resources = require('source.engine.core.resources')
    local World3D = require('source.engine.world.world')
    local Camera3D = require('source.engine.cameras.camera')
    local Renderer = require('source.engine.graphics.pipeline.renderer')
    local resources = Resources.new(require('source.game.data.manifest'))
    local ui = UI.new(200, 200, resources)
    local scroll = ui:scroll(
        { position = { 0, 20, 0, 70 }, size = { 0, 150, 0, 100 }, length = 180, scrollY = 20 },
        ui.content
    )
    local group = ui:canvasGroup({ position = { 0, 10, 0, 30 }, size = { 0, 120, 0, 120 } }, scroll)
    local button = ui:button({
        position = { 0, 10, 0, 10 },
        size = { 0, 60, 0, 30 },
        backgroundColor = { 0, 1, 0 },
        backgroundTransparency = 0.5,
        text = '',
    }, group)
    ui:create('UICorner', { cornerRadius = 8 }, group)
    ui:create('UICorner', { cornerRadius = 8 }, scroll)
    local g = katsa.graphics
    local target = g.newCanvas(200, 200, { dpiscale = 2 })
    for _, alpha in ipairs({ 0, 0.001, 0.1, 0.5, 0.999, 1 }) do
        group.transparency = alpha
        local previous
        for frame = 1, 3 do
            g.push('all')
            g.setCanvas({ target, stencil = true })
            g.setScissor()
            g.origin()
            g.clear(0, 0, 1, 1)
            ui:draw()
            g.pop()
            local data = target:newImageData()
            local _, green, blue = data:getPixel(100, 210)
            data:release()
            test:check(
                math.abs(green - 0.5 * (1 - alpha)) < 0.012
                    and math.abs(blue - (1 - 0.5 * (1 - alpha))) < 0.012,
                'CanvasGroup scrolled pixel alpha ' .. alpha .. ' frame ' .. frame
            )
            test:check(
                not previous or math.abs(previous - green) < 0.005,
                'CanvasGroup clears full target without accumulation'
            )
            previous = green
        end
        test:check(
            (ui:hit(50, 105) == button) == (alpha < 1),
            'CanvasGroup picking respects group visibility at alpha ' .. alpha
        )
    end
    target:release()
    group.transparency = 0.3
    ui:scrollBy(scroll, 40)
    ui:layout()
    test:check(
        ui:hit(button._x + 2, button._y + 2) ~= button,
        'Scrolling clips offscreen child input'
    )
    local auto = ui:scroll(
        { size = { 0, 100, 0, 60 }, automaticLength = true, contentPadding = 10 },
        ui.content
    )
    local a = ui:button({ position = { 0, 0, 0, 100 }, size = { 0, 30, 0, 40 } }, auto)
    ui:layout()
    test:check(auto.length == 150, 'Automatic Length measures position, size and trailing padding')
    local count = auto._lengthCalculations
    ui:layout()
    ui:layout()
    test:check(auto._lengthCalculations == count, 'Unchanged layout reuses Length calculation')
    a.position[4] = 180
    ui:layout()
    test:check(auto.length == 230, 'Direct component edit invalidates Length snapshot')
    ui:scrollBy(auto, 999)
    a.visible = false
    ui:layout()
    test:check(
        auto.length == 10 and auto.scrollY == 0,
        'Hidden content is excluded and scroll position clamps'
    )
    a.visible = true
    a:destroy()
    ui:layout()
    test:check(auto.length == 10, 'Removing a child updates automatic Length')
    auto.automaticLength = false
    auto.length = 300
    ui:layout()
    test:check(auto.length == 300, 'Manual Length remains authoritative')
    local presses = 0
    button:connect('press', function()
        presses = presses + 1
    end)
    group.interactable = false
    ui:pointer(button, 'press', 50, 105, 'probe')
    test:check(presses == 0, 'Interactable false cancels descendant callbacks')
    group.interactable = true
    group.enabled = false
    test:check(
        not UI.canInteract(button) and not UI.isWorking(button),
        'Enabled false suspends branch work and input'
    )
    group.enabled = true
    group.interactable = false
    test:check(UI.isWorking(button), 'Interactable false preserves UI work')
    local settings = require('source.game.data.settings').create()
    settings.sky.enabled = false
    settings.fog.enabled = false
    settings.gizmos.enabled = false
    settings.sun.enabled = false
    settings.shadows.enabled = false
    settings.toneMapping = false
    local world = World3D.new(resources, settings)
    local camera = Camera3D.new()
    camera:update(640, 360)
    local mesh = world:create('Mesh3D', {
        name = 'Support',
        position = { 10, 0, 80 },
        size = { 20, 40, 60 },
        rotation = { 0, 35, 0 },
        scale = { 2, 2, 2 },
        texture = 'white',
    })
    world:updateObject(mesh)
    local socket = world:create('Attachment3D', { name = 'Socket', position = { 0, 12, 0 } }, mesh)
    local board = world:create('BillboardUI', {
        name = 'Independent',
        adornee = socket,
        position = { 2, 3, 4 },
        offset = { 0, 18, 0 },
        offsetWorldSpace = { 0, 5, 0 },
        size = { 0, 80, 0, 40 },
        canvasSize = { 160, 80 },
    })
    board.offset.Y = 18
    board.offsetWorldSpace = { 0, 5, 0 }
    test:check(
        board.offset[2] == 18 and board.offsetWorldSpace.Y == 5 and board.position.X == 2,
        'BillboardUI Vector3 fields support named X/Y/Z and normalize assigned arrays'
    )
    local owner = board.parent
    board:update(world, camera)
    local frame = require('source.engine.world.surfaces.support').frame(board, socket)
    local bx, by, bz = require('source.engine.math.math3d').transform(frame, 2, 3, 4)
    test:check(
        math.abs(board.worldPosition[2] - (by + 23)) < 1e-5,
        'Local Offset and OffsetWorldSpace use independent world-unit translations'
    )
    local before = { unpack(board.worldPosition) }
    board.anchorPoint = { 0, 1 }
    board:update(world, camera)
    test:check(
        math.abs(board.worldPosition[1] - before[1]) < 1e-5,
        'AnchorPoint changes panel anchor without moving spatial Position'
    )
    camera.rotation = { 20, 60, 25 }
    camera:update(640, 360)
    board:update(world, camera)
    for i, base in ipairs({ bx, by, bz }) do
        test:check(
            math.abs(board.worldPosition[i] - base - (i == 2 and 18 or 0) - (i == 2 and 5 or 0))
                < 1e-4,
            'Offset is invariant under camera rotation axis ' .. i
        )
    end
    mesh.rotation[2] = 90
    board:update(world, camera)
    test:check(
        board.parent == owner and board.adornee == socket,
        'Adornee follows rotated Attachment3D without changing ownership'
    )
    local socketFrame = socket:getWorldMatrix()
    local oldY = socketFrame[8]
    socket.inheritScale = true
    local scaled = socket:getWorldMatrix()
    test:check(
        math.abs(scaled[8] - oldY - 12) < 1e-5,
        'Attachment3D inheritScale includes scaled local translation'
    )
    camera.rotation = { 0, 0, 0 }
    camera:update(640, 360)
    local extent = world:create('BillboardUI', {
        name = 'Extent',
        adornee = mesh,
        extentsOffsetWorldSpace = { 0, 1, 0 },
        size = {
            0,
            40,
            0,
            20,
        },
    })
    extent:update(world, camera)
    test:check(
        math.abs(extent.worldPosition[2] - 40) < 1e-4,
        'Extent offsets use local half dimensions and omit support rotation'
    )
    local surface = world:create(
        'SurfaceUI',
        { name = 'IndependentSurface', adornee = mesh, face = 'Top', size = { 0.5, 0, 0.5, 0 } },
        world.folders.Scripts
    )
    surface:update(world, camera)
    test:check(
        surface.parent == world.folders.Scripts and surface.worldWidth > 0,
        'Surface Face and dimensions use independent Adornee'
    )
    local decal = world:create('Decal3D', {
        name = 'IndependentDecal',
        adornee = socket,
        image = 'white',
        face = 'Front',
        supportSize = {
            6,
            4,
            2,
        },
    }, world.folders.Scripts)
    decal:update(world, camera)
    test:check(
        math.abs(decal.worldWidth - 12) < 1e-4,
        'Attachment3D surface dimensions use explicit local supportSize'
    )
    local foreign = World3D.new(resources, require('source.game.data.settings').create())
    local foreignSocket = foreign:create('Attachment3D', { name = 'Foreign' })
    test:check(
        not pcall(board.setAdornee, board, foreignSocket),
        'Cross-World3D Adornee references are rejected'
    )
    socket:destroy()
    board:update(world, camera)
    test:check(
        not board.drawable and not board.adornee and not board.destroyed and board.parent == owner,
        'Deleted Adornee hides presentation and releases reference without destroying owner'
    )
    board.adornee = mesh
    board:update(world, camera)
    test:check(
        board.adornee == mesh and board.drawable,
        'Direct Adornee assignment validates and restores presentation'
    )
    board.adornee = nil
    board:update(world, camera)
    test:check(
        board.adornee == nil and board.supportStatus == 'Ready',
        'Explicit None restores spatial Parent fallback'
    )
    -- Isolate pixel tests: the depth-hidden Mesh3D remains in the submitted candidate list.
    world:release()
    foreign:release()
    world = World3D.new(resources, settings)
    camera = Camera3D.new()
    camera:update(g.getDimensions())
    local renderer = Renderer.new(resources)
    local wall = world:create('Mesh3D', {
        name = 'Wall',
        position = { 0, 0, 25 },
        size = { 20, 20, 2 },
        color = { 0.2, 0.2, 0.2, 1 },
        texture = 'white',
        lightInfluence = 0,
    })
    local hidden = world:create('Mesh3D', {
        name = 'Hidden',
        position = { 0, 0, 50 },
        size = { 5, 5, 5 },
        color = { 1, 0, 0, 1 },
        texture = 'white',
        lightInfluence = 0,
    })

    local function sample()
        renderer:draw(world, camera, 0)
        local data = renderer.canvas:newImageData()
        local r, green, b =
            data:getPixel(math.floor(renderer.width / 2), math.floor(renderer.height / 2))
        data:release()
        return r, green, b
    end
    local red, green = sample()
    test:check(
        renderer.stats.objects == 2 and math.abs(red - green) < 0.01,
        'Stats counts frustum/layer candidates even when depth hides the rear object'
    )
    hidden.visible = false
    local red2 = sample()
    test:check(
        math.abs(red - red2) < 0.005,
        'Depth-hidden geometry does not change visible wall pixels'
    )
    wall:destroy()
    hidden:destroy()
    local brightness = world:create('BillboardUI', {
        name = 'BrightnessProbe',
        position = { 0, 0, 25 },
        size = { 0, 100, 0, 100 },
        canvasSize = { 100, 100 },
        transparency = 0.5,
    })
    brightness.ui:container(
        { size = { 1, 0, 1, 0 }, backgroundColor = { 0.2, 0.2, 0.2 } },
        brightness
    )
    local one = sample()
    brightness.brightness = 2
    local two = sample()
    test:check(
        two > one * 1.8 and two < one * 2.2 and brightness.transparency == 0.5,
        'Brightness multiplies RGB independently of Transparency'
    )
    brightness.brightness = 0
    brightness.transparency = 0
    local zero = sample()
    test:check(zero < 0.01, 'Brightness zero produces black content')
    renderer:release()
    world:release()
    ui:release()
    resources:release()
end
