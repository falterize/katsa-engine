-- Native graphics and interaction regressions. Requires LÖVE 11.5.
return function(test)
    local Resources = require('source.engine.core.resources')
    local World3D = require('source.engine.world.world')
    local UI = require('source.engine.ui')
    local V2 = require('source.engine.math.vector2')
    local U = require('source.engine.math.udim2')
    local M = require('source.engine.math.math3d')
    local Properties = require('source.engine.editor.inspectors.properties')
    local Schema = require('source.engine.editor.inspectors.schema')
    local Input = require('source.engine.input.input')

    local function check(ok, msg)
        test:check(ok, msg)
    end

    local function near(a, b)
        return math.abs(a - b) < 0.0001
    end
    local resources = Resources.new(require('source.game.data.manifest'))
    local v = V2.new(0.1, 4)
    v.Offset = 6
    check(
        v.X == 0.1 and v.Y == 6 and (v + V2.new(1, 2)).Y == 8,
        'Vector2 named components and arithmetic retain array interoperability'
    )
    local dim = U.new(0.5, 10, 0.25, -2)
    local x, y = dim:resolve(200, 100)
    check(
        x == 110 and y == 23 and (dim * 2).OffsetX == 20,
        'UDim2 resolves both Scale/Offset pairs and supports arithmetic'
    )
    local ui = UI.new(200, 160, resources)
    local group = ui:canvasGroup({ size = { 1, 0, 1, 0 }, transparency = 0.5 })
    local frame = ui:container({
        position = { 0, 20, 0, 20 },
        size = { 0, 120, 0, 80 },
        backgroundColor = { 1, 1, 1 },
        backgroundTransparency = 0.5,
    }, group)
    local corner = ui:create('UICorner', { radius = { 0.1, 4 } }, frame)
    local stroke = ui:create('UIStroke', { thickness = { 0.025, 2 }, color = { 0, 1, 0 } }, frame)
    local gradient = ui:create('UIGradient', {
        offset = { 0.2, 3, 0.1, -2 },
        colorStops = {
            { time = 0, color = { 1, 0, 0 }, transparency = 0.5 },
            { time = 1, color = { 1, 0, 0 }, transparency = 0.5 },
        },
    }, frame)
    ui:layout()
    check(near(frame._radius, 12), 'UICorner Radius uses the shorter side plus pixels')
    check(
        near(require('source.engine.ui.drawing.modifiers').thickness(stroke, frame, 64), 4),
        'UIStroke Thickness uses the same shorter side on every edge'
    )
    frame.size = { 0, 40, 0, 20 }
    corner.radius = { 1, 100 }
    ui:layout()
    check(frame._radius == 10, 'UICorner clamps Radius to half the smaller side after resize')
    frame.size = { 0, 120, 0, 80 }
    corner.radius = { 0, 0 }
    local target = love.graphics.newCanvas(200, 160, { dpiscale = 1 })
    local g = love.graphics

    local function pixels()
        g.push('all')
        g.setCanvas({ target, stencil = true })
        g.setScissor()
        g.setStencilTest()
        g.origin()
        g.clear(0, 0, 1, 1)
        ui:draw()
        g.pop()
        return target:newImageData()
    end
    local data = pixels()
    local r, green, b = data:getPixel(70, 60)
    check(
        math.abs(r - 0.125) < 0.012 and green < 0.01 and math.abs(b - 0.875) < 0.012,
        'Gradient alpha multiplies parent and CanvasGroup alpha without dimming tint'
    )
    r, green, b = data:getPixel(22, 60)
    check(green > 0.45 and r < 0.02, 'Parent gradient never changes separate UIStroke pixels')
    check(
        frame.backgroundTransparency == 0.5 and group.transparency == 0.5,
        'Gradient leaves authored parent/group transparency unchanged'
    )
    data:release()
    local sg = ui:create('UIGradient', {
        colorStops = {
            { time = 0, color = { 1, 1, 1 }, transparency = 0.5 },
            { time = 1, color = { 1, 1, 1 }, transparency = 0.5 },
        },
    }, stroke)
    data = pixels()
    r, green, b = data:getPixel(22, 60)
    check(
        math.abs(green - 0.25) < 0.025,
        'Nested UIGradient applies alpha exclusively to the stroke'
    )
    data:release()
    sg.enabled = false
    data = pixels()
    r, green, b = data:getPixel(22, 60)
    check(green > 0.45, 'Disabling nested stroke gradient removes its alpha effect')
    data:release()
    gradient.colorStops = {
        { time = 0, color = { 1, 0, 0 }, transparency = 0 },
        { time = 1, color = { 1, 0, 0 }, transparency = 1 },
    }
    gradient.offset = { 0, 0, 0, 0 }
    gradient.rotation = 0
    data = pixels()
    local leftRed = data:getPixel(30, 60)
    local rightRed = data:getPixel(130, 60)
    check(
        leftRed > rightRed + 0.15,
        'Fully transparent color stop fades alpha across the content area'
    )
    data:release()
    local clip =
        ui:container({ position = { 0, 0, 0, 0 }, size = { 0, 80, 0, 100 }, clip = true }, group)
    frame.parent = clip
    data = pixels()
    r, green, b = data:getPixel(100, 60)
    check(
        r < 0.01 and green < 0.01 and b > 0.99,
        'Gradient and border preserve ancestor scissor clipping'
    )
    data:release()
    frame.parent = group
    clip:destroy()
    gradient.colorStops = {
        { time = 0, color = { 1, 0, 0 }, transparency = 0.5 },
        { time = 1, color = { 1, 0, 0 }, transparency = 0.5 },
    }
    gradient.offset = { 0.2, 3, 0.1, -2 }
    ui:layout()
    -- Equivalent relative and absolute shifts yield the same sampled pixels.
    gradient.colorStops = { { time = 0, color = { 1, 0, 0 } }, { time = 1, color = { 0, 0, 1 } } }
    gradient.offset = { 0.1, 0, 0, 0 }
    data = pixels()
    local scaleRed = data:getPixel(60, 60)
    data:release()
    gradient.offset = { 0, 12, 0, 0 }
    data = pixels()
    local pixelRed = data:getPixel(60, 60)
    data:release()
    check(
        math.abs(scaleRed - pixelRed) < 0.006,
        'Gradient Scale and pixel Offset use equivalent target-size units'
    )
    local previous = ui:changed()
    gradient.offset.OffsetY = 8
    check(
        ui:changed() > previous,
        'In-place fourth gradient Offset component invalidates UI canvases'
    )
    previous = ui:changed()
    stroke.thickness.Scale = 0.03
    check(ui:changed() > previous, 'In-place Thickness component invalidates UI canvases')
    check(
        not pcall(ui.create, ui, 'UIStroke', {}, stroke),
        'Only gradients may nest inside UIStroke'
    )
    -- A partially transparent glyph keeps RGB while alpha decreases.
    group:destroy()
    local label = ui:text({
        position = { 0, 10, 0, 10 },
        size = { 0, 180, 0, 100 },
        fontSize = 50,
        text = 'ALPHA',
        textColor = { 1, 1, 1 },
        textTransparency = 0.5,
    }, ui.content)
    ui:create('UIGradient', {
        target = 'Text',
        colorStops = {
            { time = 0, color = { 1, 0, 0 }, transparency = 0.5 },
            { time = 1, color = { 1, 0, 0 }, transparency = 0.5 },
        },
    }, label)
    g.push('all')
    g.setCanvas({ target, stencil = true })
    g.origin()
    g.setScissor()
    g.clear(0, 0, 0, 0)
    ui:draw()
    g.pop()
    data = target:newImageData()
    local maxAlpha = 0
    local redAtMax = 0
    for yy = 10, 110 do
        for xx = 10, 190 do
            local rr, _, _, aa = data:getPixel(xx, yy)
            if aa > maxAlpha then
                maxAlpha, redAtMax = aa, rr
            end
        end
    end
    check(
        math.abs(maxAlpha - 0.25) < 0.015 and math.abs(redAtMax - 0.25) < 0.015,
        'Text gradient writes the correct premultiplied glyph alpha'
    )
    data:release()
    label:destroy()
    local image = ui:image({
        size = { 0, 120, 0, 80 },
        image = 'assets/textures/ui/litter.png',
        fitMode = 'Tile',
        tileSize = {
            0,
            20,
            0,
            15,
        },
    }, ui.content)

    local function has(target, key)
        for _, f in ipairs(Properties.list(target)) do
            if f.key == key then
                return f
            end
        end
    end
    check(
        has(image, 'tileSize') and has(image, 'tileOffset'),
        'Tile mode exposes conditional grid fields'
    )
    local oldTile = image.tileSize
    image.fitMode = 'Fit'
    check(
        not has(image, 'tileSize') and image.tileSize == oldTile,
        'Hiding a conditional property preserves its saved value'
    )
    for _, mode in ipairs({ 'Fit', 'Crop', 'Stretch', 'Tile' }) do
        image.fitMode = mode
        data = pixels()
        data:release()
        check(true, 'Native image drawing supports ' .. mode)
    end
    local nearest = resources:imageVariant(image.image, true)
    local linear = resources:imageVariant(image.image, false)
    check(
        nearest ~= linear and nearest:getFilter() == 'nearest' and linear:getFilter() == 'linear',
        'Pixel variants do not mutate shared linear images'
    )
    local ix, iy, iw, ih = require('source.engine.ui.drawing.image').rect('Fit', 100, 100, 200, 100)
    check(
        ix == 0 and iy == 25 and iw == 100 and ih == 50,
        'Fit retains aspect and centers the complete image'
    )
    ix, iy, iw, ih = require('source.engine.ui.drawing.image').rect('Crop', 100, 100, 200, 100)
    check(
        ix == -50 and iy == 0 and iw == 200 and ih == 100,
        'Crop fills the region with symmetric excess'
    )
    local settings = require('source.game.data.settings').create()
    settings.sun.enabled = false
    settings.shadows.enabled = false
    settings.sky.enabled = false
    settings.fog.enabled = false
    local world = World3D.new(resources, settings)
    local camera = world:addCamera()
    camera:update(640, 360)
    local support = world:create('Mesh3D', {
        name = 'Support',
        position = { 0, 0, 100 },
        size = { 20, 40, 10 },
        rotation = { 0, 0, 0 },
        texture = 'white',
    })
    local board = world:create('BillboardUI', {
        name = 'Panel',
        adornee = support,
        position = { 1, 2, 3 },
        offset = { 4, 5, 6 },
        offsetWorldSpace = { 7, 8, 9 },
        size = { 0.5, 20, 0, 120 },
        canvasSize = { 1, 0, 1, 0 },
        rotation = { 20, 30, 15 },
    })
    board:update(world, camera)
    board:refresh()
    board:update(world, camera)
    check(
        near(board.anchorWorldPosition[1], 12)
            and near(board.anchorWorldPosition[2], 15)
            and near(board.anchorWorldPosition[3], 118),
        'BillboardUI Position and Offset move anchor in support axes; world offset is additive'
    )
    check(
        board.resolvedCanvasSize[1] == 340 and board.resolvedCanvasSize[2] == 120,
        'Screen CanvasSize scales against resolved logical Size'
    )
    local oldAnchor = { unpack(board.anchorWorldPosition) }
    camera.rotation = { 15, 20, 25 }
    camera:update(640, 360)
    board:update(world, camera)
    check(
        near(board.anchorWorldPosition[1], oldAnchor[1])
            and near(board.anchorWorldPosition[2], oldAnchor[2]),
        'Camera3D rotation never changes BillboardUI anchor Offset'
    )
    camera.rotation = { 0, 0, 0 }
    camera:update(640, 360)
    support.rotation = { 0, 0, 90 }
    board:update(world, camera)
    check(
        near(board.anchorWorldPosition[1], 0) and near(board.anchorWorldPosition[2], 13),
        'Rotating support rotates Position plus Offset before world translation'
    )
    support.rotation = { 0, 0, 0 }
    board.position = { 0, 0, 0 }
    board.offset = { 0, 0, 0 }
    board.offsetWorldSpace = { 0, 0, 0 }
    board.extentsOffset = { 1, 0, 0 }
    board:update(world, camera)
    check(
        near(board.worldPosition[1], 10) and near(board.anchorWorldPosition[1], 0),
        'ExtentsOffset changes panel while keeping anchor unchanged'
    )
    support.rotation = { 0, 0, 90 }
    board:update(world, camera)
    check(
        near(board.worldPosition[1], 20) and near(board.worldPosition[2], 0),
        'Support rotation changes camera-aligned extent magnitude'
    )
    board.extentsOffset = { 0, 0, 0 }
    board.extentsOffsetWorldSpace = { 1, 0, 0 }
    board:update(world, camera)
    check(
        near(board.worldPosition[1], 20) and near(board.worldPosition[2], 0),
        'ExtentsOffsetWorldSpace uses world-aligned bounding dimensions'
    )
    camera.rotation = { 0, 0, 90 }
    camera:update(640, 360)
    board:update(world, camera)
    check(
        near(board.worldPosition[1], 20) and near(board.worldPosition[2], 0),
        'World3D extent displacement is independent of camera roll'
    )
    camera.rotation = { 0, 0, 0 }
    camera:update(640, 360)
    board.extentsOffsetWorldSpace = { 0, 0, 0 }
    board.anchorPoint = { 0.2, 0.7 }
    board:update(world, camera)
    board.ui:button({ name = 'PanelButton', size = { 1, 0, 1, 0 }, text = '' }, board)
    board:refresh()
    board:update(world, camera)
    local px, py, pz = M.transform(board.matrix, 0.15, 0.1, 0)
    local sx, sy = camera:project({ px, py, pz })
    local bx, by = board:localPoint(sx, sy)
    check(
        near(bx, board.resolvedCanvasSize[1] * 0.65) and near(by, board.resolvedCanvasSize[2] * 0.4),
        'Tilted BillboardUI ray picking matches actual deformed panel axes'
    )
    check(
        board:hit(world, camera, sx, sy) ~= nil,
        'Tilted panel receives a hit inside its projected plane'
    )
    board.sizeMode = 'World3D'
    board.size = { 0, 10, 0, 5 }
    board.canvasSize = { 0.5, 10, 1, 0 }
    board:update(world, camera)
    check(
        board.resolvedCanvasSize[1] == 90 and board.resolvedCanvasSize[2] == 80,
        'World3D CanvasSize uses Size times explicit pixels-per-unit'
    )
    local socket = world:create('Attachment3D', { name = 'Socket', position = { 40, 0, 100 } })
    board.adornee = socket
    board.supportSize = { 12, 8, 4 }
    board.size = { 1, 0, 1, 0 }
    board.extentsOffset = { 1, 0, 0 }
    board:update(world, camera)
    check(
        near(board.worldPosition[1] - board.anchorWorldPosition[1], 6),
        'SupportSize defines Attachment3D half extents independent of CanvasSize'
    )
    check(
        near(board.screenWidth, 12 * camera.focal / board.depth),
        'World3D Size scale uses support dimensions instead of a canvas feedback loop'
    )
    socket:destroy()
    board:update(world, camera)
    check(
        not board.drawable,
        'Deleted support hides BillboardUI and disconnects spatial presentation'
    )
    board:destroy()
    support:destroy()
    -- Triangle picking uses all occluders, not merely objects carrying detectors.
    local object = world:create(
        'Mesh3D',
        { name = 'Clickable', position = { 0, 0, 100 }, size = { 20, 20, 20 }, texture = 'white' }
    )
    local detector = world:create('ClickDetector3D', { radius = 110 }, object)
    check(
        not detector:canActivate(),
        'Missing player/source disables ClickDetector3D rather than using camera implicitly'
    )
    world:setInteractionSource(camera)
    check(detector:canActivate(), 'Explicit spectator source enables distance checks')
    local count = 0
    detector:connect('clicked', function()
        count = count + 1
    end)
    ui.width, ui.height = 640, 360
    local input = Input.new({
        world = world,
        camera = camera,
        ui = ui,
        renderer = {
            top = {},
            transparent = {},
        },
    })
    input:press('mouse', 320, 180)
    input:release('mouse', 320, 180)
    check(count == 1, 'Mouse tap on nearest 3D geometry emits clicked')
    input:press('touch', 320, 180)
    input:move('touch', 340, 180, 20, 0)
    input:release('touch', 340, 180)
    check(count == 1, 'Pointer drag cancels pending 3D click')
    local cameraInput = Input.new(
        { world = world, camera = camera, ui = ui, renderer = { top = {}, transparent = {} } },
        {
            joystick = { x = 20, y = 140, radius = 10 },
            camera = { x = 0, y = 0, width = 640, height = 360 },
            sensitivity = 0.1,
        }
    )
    cameraInput:press('look', 320, 180)
    cameraInput:move('look', 340, 185, 20, 5)
    cameraInput:release('look', 340, 185)
    check(
        count == 1 and camera.rotation[2] ~= 0,
        'Camera3D-owned drag rotates camera while canceling ClickDetector3D'
    )
    camera.rotation = { 0, 0, 0 }
    camera:update(640, 360)
    input:press('touch', 320, 180)
    input:reset()
    input:release('touch', 320, 180)
    check(count == 1, 'Focus/reset cancels pending detector tap')
    detector.radius = 99
    input:press('touch', 320, 180)
    input:release('touch', 320, 180)
    check(count == 1, 'Radius uses object spatial origin rather than nearer hit surface')
    detector.radius = 110
    local blocker = world:create(
        'Mesh3D',
        { name = 'Blocker', position = { 0, 0, 50 }, size = { 20, 20, 10 }, texture = 'white' }
    )
    input:press('touch', 320, 180)
    input:release('touch', 320, 180)
    check(count == 1, 'Closer object without detector blocks 3D interaction')
    blocker:destroy()
    local overlay =
        ui:button({ position = { 0, 300, 0, 160 }, size = { 0, 40, 0, 40 } }, ui.content)
    input:press('touch', 320, 180)
    input:release('touch', 320, 180)
    check(count == 1, 'Screen UI input prevents underlying detector activation')
    overlay:destroy()
    local decoration = ui:container({
        position = { 0, 300, 0, 160 },
        size = { 0, 40, 0, 40 },
        backgroundColor = { 1, 1, 1 },
        enabled = false,
    }, ui.content)
    input:press('touch', 320, 180)
    input:release('touch', 320, 180)
    check(count == 1, 'Disabled decorative UI also blocks 3D taps through its visible rectangle')
    decoration.backgroundTransparency = 1
    check(
        not ui:blocksWorldClick(320, 180),
        'Fully transparent empty UI leaves world taps available'
    )
    decoration:destroy()
    local visualBoard = world:create('BillboardUI', {
        name = 'VisualBlocker',
        adornee = object,
        size = { 0, 100, 0, 50 },
        canvasSize = {
            0,
            100,
            0,
            50,
        },
        onTop = true,
    })
    visualBoard.ui:text(
        { size = { 1, 0, 1, 0 }, text = 'World3D caption', backgroundColor = { 1, 1, 1 } },
        visualBoard
    )
    visualBoard:update(world, camera)
    visualBoard:refresh()
    visualBoard:update(world, camera)
    input.scene.renderer.top = { visualBoard }
    input:press('touch', 320, 180)
    input:release('touch', 320, 180)
    check(
        count == 1,
        'Decorative world UI blocks underlying ClickDetector3D without requiring a Button'
    )
    visualBoard:destroy()
    input.scene.renderer.top = {}
    detector.enabled = false
    input:press('touch', 320, 180)
    input:release('touch', 320, 180)
    check(count == 1, 'Disabled detector never captures clicks')
    detector.enabled = true
    input:press('touch', 320, 180)
    detector:destroy()
    input:release('touch', 320, 180)
    check(
        count == 1 and detector.destroyed,
        'Deletion between press and release cancels event safely'
    )
    -- Scoped types use ordinary ownership, events and update lifecycle.
    local definition = {
        base = 'Node3D',
        properties = {
            power = { default = 10, min = 0 },
            extra = { default = 7, visibleWhen = { key = 'enabled', equals = true } },
        },
        update = function(self, dt)
            self.ticks = (self.ticks or 0) + 1
        end,
    }
    world:registerNodeType('SceneProbe', definition)
    world:registerNodeType('SceneCamera', {
        base = 'Camera3D',
        properties = { power = { default = 2 } },
        update = function(self, dt)
            self.scriptTicks = (self.scriptTicks or 0) + 1
        end,
    })
    local scopedCamera = world:create('SceneCamera', { name = 'ScriptCamera', power = 6 })
    scopedCamera:update(640, 360)
    world:updateNodes(0.1)
    check(
        scopedCamera.className == 'SceneCamera'
            and scopedCamera.power == 6
            and scopedCamera.scriptTicks == 1,
        'Scoped Camera3D retains configured custom properties and separate engine/script updates'
    )
    world:registerNodeType('ScenePanel', {
        base = 'BillboardUI',
        update = function(self, dt)
            self.scriptTicks = (self.scriptTicks or 0) + 1
        end,
    })
    local scopedBoard = world:create('ScenePanel', {
        name = 'ScriptPanel',
        adornee = object,
        size = { 0, 100, 0, 50 },
        canvasSize = {
            0,
            100,
            0,
            50,
        },
    })
    scopedBoard:update(world, camera)
    world:updateNodes(0.1)
    check(
        scopedBoard.drawable and scopedBoard.scriptTicks == 1,
        'Scoped BillboardUI preserves renderer update while running game callback'
    )
    local foreign = World3D.new(resources, settings)
    foreign:registerNodeType(
        'SceneProbe',
        { base = 'Node3D', properties = { power = { default = 99 } } }
    )
    local custom = world:create('SceneProbe', { name = 'Probe', enabled = true })
    local other = foreign:create('SceneProbe', {})
    check(
        custom.power == 10 and other.power == 99,
        'Two Worlds register same type name with independent schemas/defaults'
    )
    check(
        not require('source.engine.nodes').classes.SceneProbe,
        'Scoped type never enters the global node class registry'
    )
    local scopedUI = UI.new(100, 100, resources):bindWorld(world)
    world:registerNodeType('SceneWidget', {
        base = 'Frame',
        properties = { power = { default = 4 } },
        update = function(self, dt)
            self.scriptTicks = (self.scriptTicks or 0) + 1
        end,
    })
    local customWidget = scopedUI:create('SceneWidget', { size = { 1, 0, 1, 0 } }, scopedUI.content)
    world:updateNodes(0.1)
    check(
        customWidget.power == 4 and customWidget.scriptTicks == 1 and has(customWidget, 'power'),
        'UI bound to a World3D shares scoped registration, lifecycle and property descriptors'
    )
    scopedUI:release()
    check(customWidget.destroyed, 'Scoped UI owner releases custom widget and callbacks')
    foreign:registerNodeType('SharedDefinition', definition)
    world:registerNodeType('SharedDefinition', definition)
    world.nodeTypes.SharedDefinition.propertySchema.power.default = 123
    check(
        foreign.nodeTypes.SharedDefinition.propertySchema.power.default == 10,
        'Reusable definitions are copied so schema edits cannot leak between Worlds'
    )
    check(
        not pcall(world.registerNodeType, world, 'SceneProbe', definition),
        'Duplicate type registration in one World3D reports a conflict'
    )
    check(
        not pcall(world.registerNodeType, world, 'InvalidProbe', { properties = { power = 7 } })
            and not world.nodeTypes.InvalidProbe,
        'Invalid registration fails atomically without reserving its name'
    )
    world:updateNodes(0.1)
    check(custom.ticks == 2, 'Custom update is registered with ordinary scene lifecycle')
    local field = has(custom, 'power')
    check(
        field and Properties.set({}, custom, field, '25') and custom.power == 25,
        'Custom properties are editable through the common Workspace schema'
    )
    check(
        not Properties.set({}, custom, field, '-1'),
        'Custom property descriptor validation rejects invalid values'
    )
    custom.enabled = false
    check(
        not has(custom, 'extra') and custom.extra == 7,
        'Generic conditional descriptor works for a scene-defined node'
    )
    custom:destroy()
    world:updateNodes(0.1)
    check(custom.ticks == 2, 'Destroyed custom node no longer processes')
    local decal = world:create(
        'Decal3D',
        { name = 'Modes', image = 'white', mode = 'Texture', textureSize = { 5, 10 } },
        object
    )
    decal:update(world, camera)
    check(
        has(decal, 'textureSize') and not has(decal, 'tileSize'),
        'Texture inspector exposes surface-unit repetition fields only'
    )
    local ts = decal.textureSize
    decal.mode = 'Tiles'
    decal.fitMode = 'Tile'
    check(
        has(decal, 'tileSize') and not has(decal, 'textureSize') and decal.textureSize == ts,
        'Switching Decal3D modes preserves inactive settings'
    )
    local captured = {}
    local shader = {
        hasUniform = function()
            return true
        end,
        send = function(_, k, value)
            captured[k] = value
        end,
    }
    local send = require('source.engine.graphics.pipeline.renderer').sendDecal
    decal.mode = 'Texture'
    send({}, shader, decal)
    check(
        near(captured.decalUVScale[1], 4) and near(captured.decalUVScale[2], 2),
        'Texture repeat count derives from world surface dimensions'
    )
    decal.mode = 'Tiles'
    decal.tileSize = { 0.25, 0, 0.5, 0 }
    send({}, shader, decal)
    check(
        near(captured.decalUVScale[1], 4) and near(captured.decalUVScale[2], 2),
        'Tiles repeat count derives from selected-area grid fractions'
    )
    object.size = { 40, 40, 20 }
    decal:update(world, camera)
    send({}, shader, decal)
    check(
        near(captured.decalUVScale[1], 4),
        'Tiles scale repeat cell with selected area when it grows'
    )
    decal.mode = 'Texture'
    send({}, shader, decal)
    check(
        near(captured.decalUVScale[1], 8),
        'Texture retains physical tile size when selected area grows'
    )
    decal.mode = 'Decal'
    send({}, shader, decal)
    check(
        not captured.decalRepeat and captured.decalUVScale[1] == 1,
        'Decal3D places one image instead of repeating'
    )
    require('source.game.scenes.nightPlayer.nodes.bouncePad').register(world)
    local pad = world:create('BouncePad', { name = 'ReusableTrampoline', launchSpeed = 180 })
    local velocity = { 1, 2, 3 }
    local fake = {
        getVelocity = function()
            return velocity
        end,
        setVelocity = function(_, value)
            velocity = value
        end,
    }
    pad.pendingLaunch = fake
    world:updateNodes(0.1)
    check(velocity[2] == 180, 'Reusable game BouncePad applies its exposed launch speed')
    pad.enabled = false
    pad.pendingLaunch = fake
    velocity[2] = 0
    world:updateNodes(0.1)
    check(velocity[2] == 0, 'Disabled BouncePad cannot launch a body')
    foreign:release()
    world:release()
    check(
        other.destroyed and pad.destroyed and not next(world.nodeTypes),
        'Scene release destroys custom instances and registry scope'
    )
    ui:release()
    target:release()
    resources:release()
end
