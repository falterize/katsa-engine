return function(test)
    local Resources = require('source.engine.core.resources')
    local World3D = require('source.engine.world.world')
    local UI = require('source.engine.ui')
    local Physics = require('source.engine.physics')
    local Tree = require('source.engine.editor.tree.traversal')
    local Renderer = require('source.engine.graphics.pipeline.renderer')
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.sky.enabled = false
    settings.fog.enabled = false
    settings.gizmos.enabled = false
    settings.sun.enabled = false
    local world = World3D.new(resources, settings)
    world.physics = Physics.new({ gravity = { 0, 0, 0 } })

    local function check(v, msg)
        test:check(v, msg)
    end

    local function close(a, b)
        return math.abs(a - b) < 0.0001
    end
    local camera = world:addCamera()
    camera:update(640, 360)
    local body = world:create(
        'Body3D',
        { name = 'Independent', position = { 0, 0, 60 }, size = { 8, 8, 8 }, gravityScale = 0 }
    )
    local collider = world:create('Collider3D', { shape = 'Sphere', radius = 4 }, body)
    world:updateNodes(0.01)
    check(
        #body.body.shapes == 1 and body.body.shapes[1].collider.shape == 'sphere',
        'Independent Body3D/Collider3D work without any visual Mesh3D'
    )
    local raw = body.body.raw
    collider.shape = 'Box'
    collider.size = { 10, 6, 8 }
    world:updateNodes(0.01)
    check(
        body.body.raw == raw and body.body.shapes[1].collider.size[1] == 10,
        'Collider3D resizing preserves native body identity and joints'
    )
    local old = body.body.shapes[1].raw
    check(
        not pcall(body.body.setCollider, body.body, { shape = 'Sphere', radius = -1 })
            and body.body.shapes[1].raw == old,
        'Invalid collider rebuild preserves the old shape'
    )
    collider.enabled = false
    world:updateNodes(0.01)
    check(
        body.body.colliderEnabled == false and body.body.shapes[1].raw:getCollisionMask() == 0,
        'Disabling the only Collider3D removes collisions and queries'
    )
    collider.enabled = true
    world:updateNodes(0.01)
    check(
        body.body.canCollide and body.body.canQuery,
        'Collider3D re-enable restores authored body filters'
    )
    local rows = Tree.rows({ world.root }, {}, nil, '')
    check(
        #rows < 30 and #Tree.children(body) == 1,
        'Independent body has real Collider3D children without recursive virtual Body3D rows'
    )
    local mesh = world:create(
        'Mesh3D',
        { name = 'LegacyBody', size = { 10, 10, 10 }, position = { 50, 0, 60 }, texture = 'white' }
    )
    world.physics:addBody(mesh, { type = 'Static' })
    local children = Tree.children(mesh)
    local virtual
    for _, child in ipairs(children) do
        if child.className == 'Body3D' then
            virtual = child
        end
    end
    check(virtual and #Tree.children(virtual) == 0, 'Legacy virtual Body3D inspector row is a leaf')
    check(
        #Tree.rows({ world.root }, {}, nil, 'Body3D') < 30,
        'Body3D search terminates and preserves ancestors'
    )
    local parent = world:create('Node3D', { position = { 20, 0, 0 }, rotation = { 0, 0, 90 } })
    local nested = world:create(
        'Body3D',
        { name = 'NestedPhysics', position = { 2, 0, 60 }, size = { 2, 2, 2 } },
        parent
    )
    local p = nested:getWorldPosition()
    check(
        close(p[1], 20) and close(p[2], 2),
        'Physics creation converts local pose to world under a rigid parent'
    )
    nested.body:teleport({ 30, 4, 60 })
    p = nested:getWorldPosition()
    check(
        close(p[1], 30) and close(p[2], 4) and close(nested.position[1], 4),
        'World3D physics pose converts back to local node coordinates'
    )
    parent.position[1] = 100
    p = nested:getWorldPosition()
    check(close(p[1], 30), 'Moving parent does not teleport a dynamic body')
    nested:setLocalTransform({ position = { 3, 0, 60 }, rotation = { 0, 0, 0 } })
    p = nested:getWorldPosition()
    check(
        close(p[1], 100) and close(p[2], 3),
        'Explicit local transform edit converts to a physical world teleport'
    )
    nested.position = { 5, 0, 60 }
    p = nested:getWorldPosition()
    check(
        close(p[1], 100) and close(p[2], 5),
        'Direct local Position assignment updates independent physics coherently'
    )
    local sensor = world:create('Body3D', {
        name = 'Sensor',
        bodyType = 'Static',
        position = { 0, 0, 60 },
        size = { 30, 30, 30 },
        isTrigger = true,
    })
    local entered, exited = 0, 0
    sensor:connect('triggerEntered', function(other)
        if other == body.body then
            entered = entered + 1
        end
    end)
    sensor:connect('triggerExited', function(other)
        if other == body.body then
            exited = exited + 1
        end
    end)
    world.physics:update(1 / 60)
    world.physics:update(1 / 60)
    check(
        entered == 1 and close(body:getWorldPosition()[3], 60),
        'Exact trigger emits once without physical displacement'
    )
    body.body:teleport({ 0, 0, 110 })
    world.physics:update(1 / 60)
    check(exited == 1, 'Trigger exit detects separation')
    body.body:teleport({ 0, 0, 60 })
    world.physics:update(1 / 60)
    check(entered == 2, 'Trigger can re-enter after separation')
    collider.enabled = false
    world:updateNodes(0.01)
    world.physics:update(1 / 60)
    check(exited == 2, 'A disabled collider cannot remain in trigger overlap state')
    collider.enabled = true
    world:updateNodes(0.01)
    world.physics:update(1 / 60)
    check(entered == 3, 'Re-enabled colliders may enter trigger volumes again')
    sensor:connect('triggerEntered', function(other)
        if other == nested.body then
            other:set({ type = 'Kinematic' })
            other:setCollider({ shape = 'Sphere', radius = 1 })
            other:teleport({ 30, 0, 80 })
        end
    end)
    nested.body:teleport({ 0, 0, 60 })
    world.physics:update(1 / 60)
    check(
        nested.body.type == 'kinematic'
            and nested.body.shapes[1].collider.shape == 'sphere'
            and close(nested:getWorldPosition()[3], 80),
        'Contact-time mode/shape/teleport changes are deferred safely'
    )
    sensor:connect('triggerEntered', function(other)
        if other.object.name == 'DeleteInTrigger' then
            other.object:destroy()
        end
    end)
    local doomed = world:create('Body3D', { name = 'DeleteInTrigger', position = { 0, 0, 60 } })
    world.physics:update(1 / 60)
    check(doomed.destroyed, 'Trigger callbacks may destroy bodies without corrupting the solver')
    local floor = world:create(
        'Body3D',
        { bodyType = 'Static', position = { 300, 0, 60 }, size = { 20, 2, 10 } }
    )
    local compound = world:create(
        'Body3D',
        { bodyType = 'Dynamic', position = { 300, 1.5, 60 }, gravityScale = 0 }
    )
    world:create(
        'Collider3D',
        { shape = 'Box', size = { 2, 2, 2 }, position = { -4, 0, 0 } },
        compound
    )
    world:create(
        'Collider3D',
        { shape = 'Box', size = { 2, 2, 2 }, position = { 4, 0, 0 } },
        compound
    )
    world:updateNodes(0.01)
    for i = 1, 3 do
        world.physics:update(1 / 60)
    end
    local sets = compound.body._contactSets and compound.body._contactSets[floor.body]
    local pairsCount = 0
    for _ in pairs(sets or {}) do
        pairsCount = pairsCount + 1
    end
    check(
        pairsCount == 2 and #compound.body:getContacts() == 1,
        'Compound collider reports a unique body while retaining both native shape contacts'
    )
    compound.body:teleport({ 310, 1.5, 60 })
    for i = 1, 3 do
        world.physics:update(1 / 60)
    end
    check(
        #compound.body:getContacts() == 1,
        'Ending one compound shape contact preserves the remaining body contact'
    )
    floor:destroy()
    compound:destroy()
    local light = world:create('DirectionalLight3D', {
        name = 'Directional',
        direction = { 0, -1, 1 },
        brightness = 2,
        color = { 255, 200, 180 },
        castShadow = true,
    }, parent)
    world:resolveDirectionalLight()
    check(
        world.lighting._directionalSun and world.lighting._directionalSun.brightness == 2,
        'DirectionalLight3D resolves an independent shadow-capable directional slot'
    )
    light.enabled = false
    world:resolveDirectionalLight()
    check(
        not world.lighting._directionalSun and not world.lighting.sun.enabled,
        'Disabling directional light keeps legacy sun off without disabling local lights'
    )
    world:setQualityProfile('Low')
    check(
        settings.shadows.resolution == 128 and settings.shadows.filterSamples == 1,
        'Shadow quality profile changes explicit map/filter budgets'
    )
    settings.shadows.enabled = true
    light.parent = world.folders.Lights
    light.direction = { 0.4, -1, 0.2 }
    light.enabled = true
    world:create('Mesh3D', {
        name = 'ShadowReceiver',
        kind = 'plane',
        position = { 0, -12, 80 },
        size = { 180, 1, 180 },
        texture = 'white',
    })
    local renderer = Renderer.new(resources)
    renderer:draw(world, camera, 0)
    check(
        renderer.shadows.sunEnabled
            and renderer.shadows.updatedSun
            and renderer.stats.shadowFaces == 3,
        'DirectionalLight3D renders three cascades while legacy sun is disabled'
    )
    renderer:draw(world, camera, 0)
    check(
        renderer.stats.shadowFaces == 0,
        'Static directional/geometry/camera reuse their cached maps'
    )
    light.shadowLayers = 0
    renderer:draw(world, camera, 0)
    check(renderer.shadows.updatedSun, 'Directional shadow layer edits invalidate directional maps')
    local probe =
        require('source.engine.graphics.debug.shadowProbe').measure(renderer, world, camera, 0, 1)
    check(
        probe.withSampling >= 0
            and probe.withoutSampling >= 0
            and probe.includesReadback
            and not renderer.freezeShadowUpdates,
        'Explicit shadow sampling probe restores state and separates A/B submissions'
    )
    print(
        string.format(
            'SHADOW PROBE readback-inclusive: off %.3f ms, on %.3f ms, delta %.3f ms',
            probe.withoutSampling,
            probe.withSampling,
            probe.difference
        )
    )
    local ui = UI.new(160, 100, resources)
    local frame =
        ui:container({ size = { 1, -20, 0, 40 }, backgroundColor = { 1, 1, 1 } }, ui.content)
    ui.width = 10
    ui:layout()
    check(
        frame._width == 0 and frame.layoutStatus:find('Collapsed'),
        'Responsive padding collapses to zero instead of crashing at small canvas sizes'
    )
    ui.width = 160
    ui:layout()
    check(frame._width == 140, 'Growing canvas restores original authored size')
    local fields = require('source.engine.editor.inspectors.properties')
    for _, kind in ipairs({ 'UICorner', 'UIStroke', 'UIGradient' }) do
        local modifier = ui:create(kind, {}, frame)
        local found = false
        for _, field in ipairs(fields.list(modifier)) do
            if field.key == 'visible' then
                found = true
            end
        end
        check(not found, kind .. ' inspector has Enabled but no Visible switch')
    end
    frame:destroy()
    local label = ui:text(
        { size = { 1, 0, 1, 0 }, fontSize = 60, text = 'O', textTransparency = 1 },
        ui.content
    )
    ui:create('UIStroke', { target = 'Text', thickness = { 0, 3 }, color = { 1, 0, 0 } }, label)
    local target = katsa.graphics.newCanvas(160, 100, { dpiscale = 1 })
    local g = katsa.graphics

    local function draw()
        g.push('all')
        g.setCanvas({ target, stencil = true })
        g.origin()
        g.setScissor()
        g.clear(0, 0, 0, 0)
        ui:draw()
        g.pop()
        return target:newImageData()
    end
    local data = draw()
    local red, alpha = 0, 0
    for y = 0, 99 do
        for x = 0, 159 do
            local r, _, _, a = data:getPixel(x, y)
            red = red + r
            alpha = alpha + a
        end
    end
    check(red > 5 and alpha > 5, 'Fully transparent glyph still has a visible exterior outline')
    data:release()
    -- Compare glyph footprint against a solid fill to ensure interior is carved out.
    label.textTransparency = 0
    local stroke = label:findByType('UIStroke')
    stroke.enabled = false
    data = draw()
    local inside = {}
    for y = 0, 99 do
        for x = 0, 159 do
            local _, _, _, a = data:getPixel(x, y)
            if a > 0.9 then
                inside[#inside + 1] = { x, y }
            end
        end
    end
    data:release()
    stroke.enabled = true
    label.textTransparency = 1
    ui:create('UIGradient', {
        target = 'Text',
        colorStops = {
            { time = 0, color = { 1, 1, 1 }, transparency = 1 },
            { time = 1, color = { 1, 1, 1 }, transparency = 1 },
        },
    }, label)
    data = draw()
    local interiorAlpha = 0
    for _, pixel in ipairs(inside) do
        local _, _, _, a = data:getPixel(pixel[1], pixel[2])
        interiorAlpha = math.max(interiorAlpha, a)
    end
    check(
        #inside > 10 and interiorAlpha < 0.01,
        'Transparent gradient reveals no stroke paint inside the original glyph'
    )
    data:release()
    local clip = ui:container({
        position = { 0, 30, 0, 15 },
        size = { 0, 100, 0, 70 },
        backgroundColor = { 1, 1, 1 },
        transparency = 0,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, 30 } }, clip)
    label.parent = clip
    label.position = { 0, -50, 0, -30 }
    label.visible = false
    local mask = draw()
    label.visible = true
    clip.transparency = 1
    data = draw()
    local escaped = 0
    for y = 0, 99 do
        for x = 0, 159 do
            local _, _, _, allowed = mask:getPixel(x, y)
            local _, _, _, a = data:getPixel(x, y)
            if allowed == 0 then
                escaped = math.max(escaped, a)
            end
        end
    end
    check(
        escaped < 0.01,
        'Outlined transparent glyph cannot promote pixels outside a rounded ancestor mask'
    )
    mask:release()
    data:release()
    target:release()
    ui:release()
    world.physics:release()
    world:release()
    resources:release()
end
