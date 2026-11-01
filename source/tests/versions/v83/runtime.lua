local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED v83 ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:update() end

function T:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS ' .. label)
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    local Resources = require('source.engine.core.resources')
    local World = require('source.engine.world.world')
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.engine.lighting.defaults').create()
    settings.sky.enabled, settings.fog.enabled = false, false
    settings.debug.gizmos.enabled = false
    settings.ambient, settings.toneMapping = { 0, 0, 0 }, false
    local world = World.new(resources, settings)
    world.environment.render.frameCache = false
    local camera = world:addCamera({
        position = { 0, 65, -120 },
        rotation = { -20, 0, 0 },
        drawDistance = 1000,
        layers = -1,
    })
    local renderer = require('source.engine.graphics.pipeline.renderer').new(resources)
    local ground = world:create(
        'Mesh3D',
        { name = 'Ground', position = { 0, -2, 55 }, size = { 220, 4, 200 }, castShadow = false }
    )
    local caster =
        world:create('Mesh3D', { name = 'Caster', position = { 0, 20, 55 }, size = { 25, 40, 25 } })
    local a = world:create(
        'DirectionalLight3D',
        { name = 'Key', rotation = { 65, 45, 0 }, brightness = 1, color = { 255, 100, 100 } }
    )
    local b = world:create(
        'DirectionalLight3D',
        { name = 'Fill', rotation = { 50, -50, 0 }, brightness = 1, color = { 100, 100, 255 } }
    )

    local function capture()
        renderer.lights.nextSelection = 0
        renderer.shadows.nextUpdate = -1
        renderer:draw(world, camera, 1, true)
        local data = renderer.canvas:newImageData()
        local bytes = data:getString()
        data:release()
        return bytes
    end
    self:check(not world.environment.sun, 'EnvironmentLighting has no Sun settings or fallback')
    local Tree = require('source.engine.editor.tree.traversal')
    local debugRow
    for _, row in ipairs(Tree.children(world.environment)) do
        self:check(row.name ~= 'sun', 'Environment settings omit sun row: ' .. row.name)
        if row.name == 'Debug' then
            debugRow = row
        end
    end
    local rows = Tree.children(debugRow)
    self:check(
        rows[1].name == 'Physics3D' and rows[2].name == 'Gizmos' and rows[1].parent == rows[2].parent,
        'Physics and gizmos share the Debug parent'
    )
    world.physics = require('source.engine.physics').new()
    world.environment.debug.physics.enabled = true
    self:check(world.physics.debugEnabled, 'Physics debug uses the shared enabled setting')
    world.physics.debugEnabled = false
    self:check(
        not world.environment.debug.physics.enabled,
        'Previous physics debug API stays synchronized'
    )
    local fields = {}
    for _, f in
        ipairs(
            require('source.engine.editor.inspectors.properties').list(
                world.environment.debug.physics
            )
        )
    do
        fields[f.key] = f
    end
    self:check(
        fields.drawShapes and fields.drawContacts and fields.drawJoints,
        'Physics flags are editable in Workspace'
    )
    fields = {}
    for _, f in ipairs(require('source.engine.editor.inspectors.properties').list(a)) do
        fields[f.key] = f
    end
    self:check(
        fields.rotation and not fields.direction,
        'Directional orientation exposes Rotation only'
    )
    local dark = capture()
    self:check(
        renderer.lights.count == 2 and a.slot ~= b.slot,
        'Two directional nodes occupy independent shared light slots'
    )
    b.enabled = false
    local key = capture()
    self:check(dark ~= key, 'Second directional source contributes actual pixels')
    a.enabled = false
    local unlit = capture()
    self:check(
        unlit ~= key and renderer.lights.count == 0,
        'Disabling all directional nodes removes their light'
    )
    a.enabled, b.enabled = true, true
    a.rotation = { 90, 0, 0 }
    capture()
    self:check(
        math.abs(a.worldDirection[2] + 1) < 1e-6,
        'Rotation X=90 points light rays down the Y axis'
    )
    local parent = world:create('Node3D', { rotation = { 0, 0, 30 } })
    a.parent = parent
    capture()
    self:check(math.abs(a.worldDirection[1]) > 0.4, 'Parent rotation changes directional rays')
    a.parent = world.folders.Lights
    a.rotation = { 65, 45, 0 }
    world.environment.lightSettings.maxActiveLights = 1
    b.priority = 10
    capture()
    self:check(
        renderer.lights.count == 1 and renderer.lights.selected[1] == b,
        'Directional priority resolves a shared slot limit'
    )
    world.environment.lightSettings.maxActiveLights = 4
    world.environment.shadows.enabled = true
    world.environment.shadows.resolution = 128
    world.environment.shadows.sourceFadeSeconds = 0
    world.environment.shadows.maxUpdateFaces = 195
    world.environment.shadows.visibleFacesOnly = false
    local shadowed = capture()
    self:check(
        renderer.shadows.updatedFaces == 6 and renderer.shadows.updatedLights == 2,
        'Each directional source builds three independent cascades'
    )
    self:check(
        renderer.shadows.lightData[a.slot][1] ~= renderer.shadows.lightData[b.slot][1]
            and renderer.shadows.lightData[a.slot][3] == 7
            and renderer.shadows.lightData[b.slot][3] == 7,
        'Directional cascade bases are separate and published atomically'
    )
    a.castShadow, b.castShadow = false, false
    local clear = capture()
    self:check(shadowed ~= clear, 'Multiple directional shadow maps darken actual pixels')
    a.castShadow = true
    local onlyA = capture()
    a.castShadow, b.castShadow = false, true
    local onlyB = capture()
    self:check(
        onlyA ~= clear and onlyB ~= clear and onlyA ~= onlyB,
        'Each directional source independently casts a visible shadow'
    )
    a.castShadow, b.castShadow = true, true
    capture()
    capture()
    self:check(renderer.shadows.updatedFaces == 0, 'Unchanged directional maps reuse the atlas')
    a.rotation[2] = a.rotation[2] + 15
    capture()
    self:check(
        renderer.shadows.updatedFaces == 3,
        'Rotating one directional source rebuilds only its cascades'
    )
    a.position[1] = 500
    capture()
    self:check(
        renderer.shadows.updatedFaces == 0,
        'Directional Position does not affect illumination or shadows'
    )
    camera.position[1] = camera.position[1] + 30
    capture()
    self:check(
        renderer.shadows.updatedFaces == 6,
        'Camera motion refreshes both snapped directional projections'
    )
    world:create(
        'PointLight3D',
        { name = 'Point', position = { 0, 70, 40 }, range = 250, brightness = 2, castShadow = true }
    )
    world:create('SpotLight3D', {
        name = 'Spot',
        position = { 20, 85, 0 },
        rotation = { 40, 0, 0 },
        range = 250,
        radius = 160,
        castShadow = true,
    })
    capture()
    self:check(
        renderer.lights.count == 4 and renderer.shadows.updatedFaces >= 7,
        'Directional, Point and Spot share the renderer and atlas'
    )
    local masks = require('source.engine.graphics.pipeline.lightMasks')
    masks.update({ caster }, renderer.lights)
    local bit = require('bit')
    local packed = caster._lightPalette[1] + caster._lightPalette[2] * 65536
    self:check(
        bit.band(packed, bit.lshift(1, a.slot - 1)) ~= 0
            and bit.band(packed, bit.lshift(1, b.slot - 1)) ~= 0,
        'Masked light loop always includes selected directional sources'
    )
    world.environment.render.lightLoop = 'Masked'
    local masked = capture()
    world.environment.render.lightLoop = 'Direct'
    self:check(masked == capture(), 'Direct and Masked render identical mixed-light pixels')
    -- Real particle shaders compile and receive directional slots through the same light data.
    local emitter = world:create('ParticleEmitter3D', {
        position = { 0, 20, 35 },
        rate = 0,
        maxParticles = 4,
        lifetime = { 1, 1 },
        receiveShadow = true,
    })
    emitter:emit(1)
    world.particles:update(0.02)
    capture()
    self:check(true, 'Particles render with multiple directional lights and cascades')
    -- Debug drawing belongs to the rendered world, including offscreen Viewports.
    local body = world:create(
        'Body3D',
        { name = 'DebugBody', bodyType = 'Static', position = { 0, 20, 55 } }
    )
    world:create('Collider3D', { shape = 'Box', size = { 25, 40, 25 } }, body)
    world.environment.debug.physics.drawShapes = true
    world.environment.debug.physics.enabled = true
    local physicsImage = capture()
    world.environment.debug.physics.enabled = false
    self:check(physicsImage ~= capture(), 'Physics debug lines render inside the world canvas')
    renderer:release()
    world:release()
    resources:release()
    require('source.tests.integration.shadowCacheRuntime')(self)
    for _, zone in ipairs({
        'shadows',
        'occlusion',
        'surfaceGallery',
        'modelLab',
        'platformer',
        'viewports',
        'nightPlayer',
    }) do
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
        assert(scene, err)
        scene.world.environment.shadows.resolution = 64
        scene.world.environment.shadows.maxUpdateFaces = 195
        scene.renderer:draw(scene.world, scene.camera, 1, true)
        if zone == 'viewports' then
            scene.ui:draw()
        end
        if zone == 'shadows' then
            scene.demo.directionalShadow.enabled = true
            scene.demo.directionalFill.enabled = true
            scene.renderer.lights.nextSelection = 0
            scene.renderer:draw(scene.world, scene.camera, 1, true)
            self:check(
                scene.demo.directionalShadow.selected and scene.demo.directionalFill.selected,
                'Shadows example exposes two simultaneously working directional sources'
            )
        end
        self:check(
            scene.world.environment.sun == nil,
            'Migrated example renders without fallback Sun: ' .. zone
        )
    end
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' focused v83 checks')
    if self.finish then
        self:finish()
    else
        katsa.event.quit()
    end
end

return T
