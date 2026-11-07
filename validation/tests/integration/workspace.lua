return function(test, scene)
    local C = require('source.engine.math.cframe')
    local V = require('source.engine.math.vector3')
    local frame = C.new(3, 8, -2) * C.fromEulerAngles(0.3, -0.7, 0.9)
    local point = V.new(2, 4, 8)
    test:check(
        (frame:pointToObjectSpace(frame * point) - point):magnitude() < 1e-8,
        'CFrame inverse and point round-trip'
    )
    local x, y, z = frame:toEulerAngles()
    test:check(
        (C.fromEulerAngles(x, y, z):lookVector() - frame:lookVector()):magnitude() < 1e-8,
        'CFrame Euler conversion matches engine convention'
    )
    local mid = C.new():lerp(C.fromAxisAngle({ 0, 1, 0 }, math.pi / 2), 0.5)
    test:check(
        math.abs(mid:lookVector()[1] - math.sqrt(0.5)) < 1e-8,
        'CFrame spherical rotation interpolation'
    )
    test:check(
        (C.lookAt({ 0, 0, 0 }, { 0, 0, 2 }):lookVector() - V.new(0, 0, 1)):magnitude() < 1e-8,
        'CFrame positive Z lookAt'
    )
    local parent =
        scene.world:create('Node3D', { name = 'TransformParent', position = { 10, 0, 0 } })
    local folder = scene.world:create('Folder', { name = 'NestedFolder' }, parent)
    local child = scene.world:create('Attachment3D', { position = { 2, 0, 0 } }, folder)
    test:check(
        child:getWorldPosition()[1] == 12,
        'Spatial transforms pass through organizational folders'
    )
    parent.size = { 4, 4, 4 }
    parent:setCFrame(C.new(10, 20, 30) * C.fromEulerAngles(0, math.pi / 2, 0))
    child.position = { 0, 3, 0 }
    child:setCFrame(C.new(0, 3, 0) * C.fromEulerAngles(0.2, 0, 0))
    local camera = scene.world:create('Camera3D', { name = 'SocketCamera' }, child)
    local offset = C.new(1, 2, 3) * C.fromEulerAngles(0.1, 0.3, 0.2)
    camera:setCFrame(offset)
    camera:update(katsa.graphics.getDimensions())
    local expected = child:getWorldCFrame() * offset
    test:check(
        (camera:getWorldCFrame():position() - expected:position()):magnitude() < 1e-6
            and (camera:getWorldCFrame():lookVector() - expected:lookVector()):magnitude()
                < 1e-6,
        'Attachment3D composes camera local position and rotation without mesh scale'
    )
    local light =
        scene.world:create('SpotLight3D', { name = 'SocketLight', position = { 1, 2, 3 } }, child)
    local board = scene.world:create(
        'BillboardUI',
        { name = 'SocketBillboard', position = { 1, 2, 3 } },
        child
    )
    board:update(scene.world, scene.camera)
    test:check(
        (V.new(unpack(light:getWorldPosition())) - expected:position()):magnitude() < 1e-6
            and (V.new(unpack(board.worldPosition)) - expected:position()):magnitude() < 1e-6,
        'Light and BillboardUI offsets inherit Attachment3D rotation and translation'
    )
    test:check(not pcall(function()
        scene.ui:button({ width = 8, height = 8 }, child)
    end), 'Screen widgets cannot be parented to Attachment3D')
    parent.position[1] = parent.position[1] + 7
    camera:update(katsa.graphics.getDimensions())
    board:update(scene.world, scene.camera)
    test:check(
        math.abs(camera.worldPosition[1] - expected:position()[1] - 7) < 1e-6
            and math.abs(board.worldPosition[1] - camera.worldPosition[1]) < 1e-6,
        'Moving a spatial parent moves all socket descendants'
    )
    parent:destroy()
    test:check(
        scene.world.objects[1].parent == scene.world.root
            and scene.camera.parent == scene.world.root,
        'World3D nodes sit directly under the world root, without category folders'
    )
    scene.debugOverlay.visible = true
    local bx, by = scene.ui:position(scene.debugButton)
    bx = scene.ui.offsetX + (bx + 20) * scene.ui.scale
    by = scene.ui.offsetY + (by + 20) * scene.ui.scale
    test:check(
        scene.ui:hit(bx, by) == scene.debugButton,
        'Debug toggle remains the topmost input target over the open menu'
    )
    scene.input:press('debug-toggle', bx, by)
    scene.input:release('debug-toggle')
    test:check(not scene.debugOverlay.visible, 'Visible Debug button closes its open menu')
    local editor = scene.workspace
    editor:toggle(true)
    editor:update(0.125)
    test:check(
        editor.progress == 0.5 and editor.panel.x > 520 and editor.panel.x < 1280,
        'Workspace has reversible smooth opening'
    )
    editor:toggle(false)
    editor:update(0.3)
    test:check(editor.progress == 0 and not editor.panel.visible, 'Workspace closes smoothly')
    editor:toggle(true)
    editor:update(0.3)
    local object = scene.world.objects[1]
    editor:select(object)
    local properties = require('source.engine.editor.inspectors.properties')
    local field = { key = 'position', kind = 'vector' }
    local previous = object.position[1]
    test:check(
        properties.set(scene, object, field, '42', 1) and object.position[1] == 42,
        'Inspector edits live vector components'
    )
    properties.set(scene, object, field, tostring(previous), 1)
    local originalName = object.name
    local before = object.transparency
    test:check(
        not properties.set(scene, object, { key = 'transparency', kind = 'number' }, '5')
            and object.transparency == before,
        'Inspector rejects invalid input without mutation'
    )
    editor:beginEdit({ key = 'name', kind = 'string' })
    editor:textinput('TestName')
    editor:commit()
    test:check(scene.world.byName.TestName == object, 'Inspector rename updates resource indexes')
    properties.set(scene, object, { key = 'name', kind = 'string' }, originalName)
    -- Return to the existing scene state before the original runtime assertions.
    editor:toggle(false)
    editor:update(0.3)
end
