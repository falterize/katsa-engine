local Application = require('source.game.runtime.application')
local Surface = require('source.engine.materials.surface')
local Layers = require('source.engine.world.visibilityLayers')
local Tests = {}

local function near(a, b, tolerance)
    return math.abs(a - b) < (tolerance or 0.01)
end

function Tests.layers(tester)
    local world, ui, physics, body, release = tester:environment()
    world.layerGroups:add('TestViewer')
    world.layerGroups:add('TestHidden')
    world.layerGroups:set('TestViewer', 'TestHidden', false)
    local camera = ui:create('Camera2D', { layerGroup = 'TestViewer' })
    local object = body(50, 50, 'Static')
    local visual = ui:create('Button', { size = { 1, 0, 1, 0 }, layerGroup = 'TestHidden' }, object)
    local x, y = ui:worldToScreen2D(50, 50)
    tester:check(
        not ui:layerVisible(visual) and ui:hit(x, y) ~= visual,
        'Camera2D layer groups filter spatial UI rendering and pointer input'
    )
    camera.layerGroup = 'Default'
    tester:check(
        ui:layerVisible(visual) and ui:hit(x, y) == visual,
        'Changing the camera layer restores its spatial UI'
    )
    local hud = ui:button({ size = { 0, 60, 0, 40 }, layerGroup = 'TestHidden' }, ui.content)
    ui.layerGroup = 'TestViewer'
    tester:check(
        not ui:layerVisible(hud) and ui:hit(10, 10) ~= hud,
        'World2D layer groups independently filter camera-independent HUD widgets'
    )
    local rectangle =
        ui:container({ position = { 0, 100, 0, 0 }, size = { 0, 40, 0, 40 } }, ui.content)
    ui:create('UICorner', { layerGroup = 'TestHidden', radius = { 0, 12 } }, rectangle)
    ui:layout()
    tester:check(not rectangle._rounded, 'Layer-hidden UI modifiers do not affect visual layout')
    world.layerGroups:set('TestViewer', 'TestHidden', true)
    ui:layout()
    tester:check(rectangle._rounded, 'Enabling a modifier layer restores its visual effect')
    tester:check(ui:layerVisible(hud), 'Layer matrix changes invalidate visibility caches')
    local mesh =
        world:create('Mesh3D', { name = 'LayeredMaterial', geometry = world.geometry.cube })
    local material = world:create('SurfaceAppearance3D', { layerGroup = 'TestHidden' }, mesh)
    world._materialCamera = { layerGroup = 'TestViewer' }
    world.layerGroups:set('TestViewer', 'TestHidden', false)
    tester:check(
        Surface.resolve(world, mesh) == nil,
        'SurfaceAppearance3D layer group filters its material contribution'
    )
    world._materialCamera.layerGroup = 'Default'
    tester:check(
        Surface.resolve(world, mesh) == material,
        'A visible material layer contributes to the mesh normally'
    )
    world.layerGroups:rename('TestHidden', 'RenamedMaterial')
    tester:check(
        hud.layerGroup == 'RenamedMaterial'
            and material.layerGroup == 'RenamedMaterial'
            and Layers.visible(world, material, world._materialCamera),
        'Layer group renames update UI and material nodes together'
    )
    camera.rotation = 0
    local _, center = camera:worldToScreen(0, 0, ui.width, ui.height)
    local _, above = camera:worldToScreen(0, 10, ui.width, ui.height)
    tester:check(above < center, 'Positive spatial Y projects upward in Camera2D')
    local image = love.image.newImageData(8, 8)
    for iy = 0, 3 do
        for ix = 0, 7 do
            image:setPixel(ix, iy, 1, 1, 1, 1)
        end
    end
    assert(love.filesystem.createDirectory('validation-v1071'))
    local imagePath = 'validation-v1071/topOnly.png'
    image:encode('png', imagePath)
    local mask = body(300, 0, 'Static')
    ui:create('Collider2D', { shape = 'Image', image = imagePath, size = { 32, 32 } }, mask)
    physics:update(0)
    tester:check(
        #physics:overlapPoint({ 300, 10 }) == 1 and #physics:overlapPoint({ 300, -10 }) == 0,
        'Image collider top pixels map to positive local Y'
    )
    image:release()
    release()
    love.filesystem.remove(imagePath)
end

local function advance(scene, count)
    for _ = 1, count do
        scene:update(1 / 60, 1 / 60)
    end
end

function Tests.scenes(tester)
    for _, name in ipairs({ 'physics2D', 'physicsMixed', 'abilityRunner2D' }) do
        local scene = Application.new(tester.manager, name)
        scene:load()
        tester:check(
            scene.demo.controlsPanel and not scene.demo.controlsPanel.visible,
            name .. ': scene controls start inside the common collapsible panel'
        )
        tester:check(
            scene.ui.autoUpdatePhysics == false and scene.systems:isEnabled('simulation'),
            name .. ': scene simulation system explicitly owns the 2D solver'
        )
        if name ~= 'physicsMixed' then
            tester:check(
                not scene.cameraButtons[1].visible and not scene.cameraButtons[2].visible,
                name .. ': inactive 3D camera movement buttons stay hidden'
            )
        end
        local object = scene.demo.ball or scene.demo.player
        object.body:teleport(100, 300)
        object.body:setVelocity({ 30, 0 })
        scene.systems:setEnabled('simulation', false)
        local x, y = object.body:getPosition()
        advance(scene, 5)
        local px, py = object.body:getPosition()
        tester:check(
            x == px and y == py,
            name .. ': disabling simulation freezes native 2D physics'
        )
        scene.systems:setEnabled('simulation', true)
        advance(scene, 5)
        _, py = object.body:getPosition()
        tester:check(py < y, name .. ': negative Y gravity falls downward after resuming')
        scene.world.debug.orientation2D, scene.world.debug.orientation3D = true, true
        scene:draw()
        tester:check(true, name .. ': both camera orientation indicators draw successfully')
        scene:release()
    end
    local scene = Application.new(tester.manager, 'abilityRunner2D')
    scene:load()
    local state, controller = scene.demo, scene.demo.controller
    local Image = require('source.engine.components.image')
    local Schema = require('source.engine.editor.inspectors.schema')
    tester:check(
        state.sprite.imageMode == 'XML' and state.sprite.xml == 'scene://animations/player.xml',
        'Runner authors its XML image mode and manifest path directly on the sprite'
    )
    tester:check(
        Schema.visible(state.sprite, 'xml')
            and Schema.visible(state.sprite, 'atlasFrame')
            and not Schema.visible(state.sprite, 'atlasGrid'),
        'XML inspector shows manifest and editable frame while hiding automatic grid settings'
    )
    local binding = state.sprite._xmlBinding
    local selected = state.sprite.atlasFrame
    state.sprite.atlasFrame = 5
    local resolved = Image.resolve(scene.resources, state.sprite)
    local ax, ay, aw, ah = Image.region(state.sprite, resolved:getDimensions())
    tester:check(
        ax == 40 and ay == 0 and aw == 8 and ah == 8,
        'XML resolves its PNG automatically and selects the requested zero-based frame'
    )
    Image.resolve(scene.resources, state.sprite)
    tester:check(
        state.sprite.atlasFrame == 5
            and state.sprite._xmlBinding == binding
            and state.sprite.imageMode == 'XML',
        'Repeated XML rendering reuses validated metadata and preserves manual frame selection'
    )
    tester:check(
        Schema.visible(state.sprite, 'image')
            and Schema.descriptor(state.sprite, 'image').get(state.sprite)
                == 'scene://textures/player.png',
        'XML automatically fills its editable image path from the manifest'
    )
    for _, mode in ipairs({ 'Decal', 'Texture', 'Tiles', 'Atlas', 'XML' }) do
        state.sprite.imageMode = mode
        tester:check(
            Image.resolve(scene.resources, state.sprite) == resolved,
            'Leaving XML retains the manifest sprite in ' .. mode .. ' mode'
        )
        scene:draw()
    end
    local variantPath = 'validation-v1071/player-variant.png'
    local pixels = love.image.newImageData(64, 8)
    pixels:mapPixel(function()
        return 1, 0.2, 0.4, 1
    end)
    pixels:encode('png', variantPath)
    pixels:release()
    state.sprite.image = variantPath
    local variant = Image.resolve(scene.resources, state.sprite)
    tester:check(
        variant ~= resolved
            and state.sprite._xmlBinding.definition == binding.definition
            and state.sprite.atlasFrame == 5,
        'A separate image path overrides XML art without reparsing metadata or resetting the frame'
    )
    for _, mode in ipairs({ 'Decal', 'Texture', 'Tiles', 'Atlas', 'XML' }) do
        state.sprite.imageMode = mode
        tester:check(
            Image.resolve(scene.resources, state.sprite) == variant,
            'An explicit XML image override survives switching to ' .. mode
        )
        scene:draw()
    end
    local journal = scene.resources.store.journal
    local diagnostics = require('source.engine.debug.journal').new()
    scene.resources.store.journal = diagnostics
    state.sprite.image = 'white'
    tester:check(
        pcall(Image.resolve, scene.resources, state.sprite) and state.sprite._imageMissing,
        'An incompatible XML sprite uses a diagnostic texture without stopping the scene'
    )
    state.sprite.image = ''
    tester:check(
        Image.resolve(scene.resources, state.sprite) == resolved,
        'Clearing an image override restores the manifest sprite'
    )
    tester:check(
        state.sprite.image == 'scene://textures/player.png',
        'Clearing the override fills the image field from XML again'
    )
    local manifestPath = 'validation-v1071/player-variant.xml'
    local manifest = assert(love.filesystem.read(scene.resources:canonical(state.sprite.xml)))
    love.filesystem.write(manifestPath, (manifest:gsub('scene://textures/player.png', variantPath)))
    local originalXml = state.sprite.xml
    state.sprite.xml = manifestPath
    Image.resolve(scene.resources, state.sprite)
    tester:check(
        state.sprite.image == variantPath,
        'Changing XML updates a previously automatic image path'
    )
    state.sprite.image = 'scene://textures/player.png'
    state.sprite.xml = originalXml
    Image.resolve(scene.resources, state.sprite)
    tester:check(
        state.sprite.image == 'scene://textures/player.png',
        'Changing XML preserves a manually selected image override'
    )
    local absent = 'scene://textures/not-installed.png'
    state.sprite.image = absent
    local missing = Image.resolve(scene.resources, state.sprite)
    local mx, my, mw, mh = Image.region(state.sprite, missing:getDimensions())
    tester:check(
        state.sprite._imageMissing
            and mx == 0
            and my == 0
            and mw == missing:getWidth()
            and mh == missing:getHeight(),
        'Missing XML images use the complete checker instead of failing atlas-size validation'
    )
    scene:draw()
    local empty = scene.ui:create('ImageLabel', { size = { 0, 32, 0, 32 } }, scene.ui.content)
    scene:draw()
    tester:check(empty._imageMissing, 'An ImageLabel without image renders a diagnostic texture')
    empty.image = ''
    scene:draw()
    tester:check(empty._imageMissing, 'An empty ImageLabel path renders without crashing')
    empty:destroy()
    local emptyButton =
        scene.ui:create('Button', { image = '', size = { 0, 32, 0, 32 } }, scene.ui.content)
    scene:draw()
    tester:check(
        emptyButton._imageMissing,
        'Explicitly empty button images show the checker while ordinary text buttons remain unchanged'
    )
    emptyButton:destroy()
    tester:check(
        scene.resources:image(nil) == scene.resources:image('')
            and scene.resources:isMissingImage(nil)
            and scene.resources:isMissingImage(''),
        'Resource APIs share a cached diagnostic image for absent and empty paths'
    )
    local bad = scene.resources:image('README.md')
    tester:check(
        bad ~= nil and scene.resources:isMissingImage('README.md'),
        'Undecodable image files retain the existing diagnostic fallback'
    )
    local canvas = love.graphics.newCanvas(missing:getDimensions())
    love.graphics.push('all')
    love.graphics.setCanvas(canvas)
    love.graphics.setShader()
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(missing)
    love.graphics.pop()
    local data = canvas:newImageData()
    local black, purple = false, false
    for iy = 0, data:getHeight() - 1 do
        for ix = 0, data:getWidth() - 1 do
            local r, g, b, alpha = data:getPixel(ix, iy)
            black = black or r < 0.01 and g < 0.01 and b < 0.01 and alpha > 0.99
            purple = purple or r > 0.6 and g < 0.01 and b > 0.8 and alpha > 0.99
        end
    end
    tester:check(
        black and purple and missing:getFilter() == 'nearest',
        'Missing-image pixels contain opaque black/purple checks with sharp filtering'
    )
    data:release()
    canvas:release()
    local Models = require('source.engine.import.models')
    local model = Models.load('scene://models/not-installed.glb', scene.resources)
    local another = Models.load('scene://models/not-installed.glb', scene.resources)
    tester:check(
        model.missing and model ~= another and model.parts[1].geometry == another.parts[1].geometry,
        'Missing models produce independent instances with shared placeholder geometry'
    )
    Models.instantiate(scene.world, model, { name = 'MissingModelTest' })
    local mesh = model.objects[1]
    scene.world:updateObject(mesh)
    tester:check(
        mesh.geometry.mesh ~= nil
            and mesh._surfaceAppearance ~= nil
            and scene.resources:isMissingImage(mesh._surfaceAppearance.colorMap),
        'A missing model mounts as a visible checker-textured mesh'
    )
    local diagnostic
    local probe = {
        hasUniform = function()
            return true
        end,
        send = function(_, name, value)
            if name == 'surfaceDiagnosticBounds' then
                diagnostic = { unpack(value) }
            end
        end,
    }
    Surface.bind(probe, scene.world, mesh)
    tester:check(
        diagnostic and math.abs(diagnostic[4] - 12) < 0.00001,
        'Unit placeholder uses twelve diagnostic cells instead of four world-unit cells'
    )
    mesh.position, mesh.scale = { 100, 200, 300 }, { 0.01, 0.01, 0.01 }
    Surface.bind(probe, scene.world, mesh)
    tester:check(
        diagnostic and math.abs(diagnostic[4] - 12) < 0.00001,
        'Small translated meshes retain their object-local diagnostic pattern'
    )
    local decal = scene.world:create('Decal3D', { name = 'MissingDecalTest' }, mesh)
    tester:check(
        decal._imageMissing and decal.textureImage ~= nil,
        'Decal3D can mount with an absent image and uses the same diagnostic texture'
    )
    mesh._surfaceAppearance.colorMap = 'white'
    Surface.image(scene.resources, mesh._surfaceAppearance, 'colorMap')
    tester:check(
        not mesh._surfaceAppearance._imageMissing,
        'Restoring a valid mesh texture clears the missing-image diagnostic state'
    )
    model.root:destroy()
    local emptyModel = Models.load(nil, scene.resources)
    tester:check(
        emptyModel.missing and #emptyModel.parts == 1,
        'An absent model path produces a placeholder instead of a crash'
    )
    tester:check(
        #diagnostics.entries > 0,
        'Missing assets retain resource diagnostics without terminating the scene'
    )
    scene.resources.store.journal = journal
    state.sprite.image = ''
    Image.resolve(scene.resources, state.sprite)
    state.sprite.atlasFrame = selected
    state.sprite.imageMode = 'Atlas'
    tester:check(
        not Schema.visible(state.sprite, 'xml') and Schema.visible(state.sprite, 'atlasGrid'),
        'Manifest path is hidden outside XML image mode'
    )
    state.sprite.imageMode = 'XML'
    local button = scene.ui:create(
        'Button',
        { imageMode = 'XML', xml = state.sprite.xml, size = { 0, 16, 0, 16 } },
        scene.ui.content
    )
    scene:draw()
    tester:check(
        button._xmlBinding ~= nil,
        'Image-bearing buttons render XML without a separate image property'
    )
    button:destroy()
    local mesh =
        scene.world:create('Mesh3D', { name = 'XmlTestMesh', geometry = scene.world.geometry.cube })
    local surface = scene.world:create(
        'SurfaceAppearance3D',
        { name = 'XmlTestSurface', imageMode = 'XML', xml = state.sprite.xml },
        mesh
    )
    local colorMap = Surface.image(scene.resources, surface, 'colorMap', scene.world.environment)
    tester:check(
        colorMap == resolved and surface.atlasGrid[1] == 8,
        'SurfaceAppearance3D shares XML atlas resolution for its color map'
    )
    mesh:destroy()
    local previous = state.sprite.xml
    state.sprite.xml = 'scene://animations/missing.xml'
    tester:check(
        pcall(Image.resolve, scene.resources, state.sprite) and state.sprite._imageMissing,
        'An invalid manifest uses a diagnostic texture while retaining the error report'
    )
    state.sprite.xml = previous
    local checkpointSounds, play = 0, scene.audio.play
    scene.audio.play = function(audio, path, options)
        if path == 'shared://audio/effects/chime.wav' then
            checkpointSounds = checkpointSounds + 1
        end
        return play(audio, path, options)
    end
    advance(scene, 50)
    tester:check(controller.grounded, 'Runner rests on a Box2D platform with Y-up coordinates')
    controller:request('jump')
    advance(scene, 1)
    local _, vy = state.player.body:getLinearVelocity()
    tester:check(vy > 250 and controller.jumps == 1, 'Runner jumps upward through native physics')
    controller:request('jump')
    advance(scene, 1)
    tester:check(controller.jumps == 2, 'Runner supports a second airborne jump')
    controller:request('jump')
    advance(scene, 1)
    tester:check(controller.jumps == 2, 'Runner rejects a third airborne jump')
    controller:request('dash')
    advance(scene, 1)
    local vx = state.player.body:getLinearVelocity()
    tester:check(
        vx > 400 and controller.motion == 'Dash',
        'Runner dash uses its own animation state'
    )
    tester:check(
        state.trail.rate == 100 and state.trail:isA('ParticleEmitter2D'),
        'Runner dash emits the adapted 3D trail at the original rate'
    )
    state.player.body:teleport(590, 125)
    state.player.body:setVelocity({ 0, 0 })
    advance(scene, 2)
    tester:check(state.checkpoint == 1, 'Entering a checkpoint trigger saves the new spawn point')
    tester:check(
        #state.burst.particles == 40,
        'A new runner checkpoint emits the original forty-particle burst'
    )
    controller:checkpoint(1)
    tester:check(
        checkpointSounds == 1,
        'A newly reached checkpoint plays the shared 3D runner chime exactly once'
    )
    scene.audio.play = play

    local deaths = state.deaths
    state.player.body:teleport(400, -100)
    advance(scene, 3)
    local x, y = state.player.body:getPosition()
    tester:check(
        state.deaths == deaths + 1 and near(x, 590, 10) and y > 100,
        'Kill-zone trigger respawns the player at the saved checkpoint'
    )
    state.player.body:teleport(100, 17)
    state.player.body:setVelocity({ 0, 0 })
    advance(scene, 5)
    controller:request('slide')
    advance(scene, 1)
    tester:check(
        state.collider.size[2] == 16,
        'Slide shrinks the physical collider while keeping its feet fixed'
    )
    local animation = scene.systems.named.animation.system.flipbook
    tester:check(
        animation.source == 'scene://animations/player.xml',
        'Runner animation clips load from the scene-owned XML manifest'
    )
    animation:play('Run', true)
    local frame = state.sprite.atlasFrame
    animation:update(0.11)
    tester:check(
        state.sprite.atlasFrame ~= frame,
        'Run animation advances the authored 8x8 atlas frames'
    )
    local image = scene.resources:image('scene://textures/player.png')
    tester:check(
        image:getWidth() == 64 and image:getHeight() == 8 and state.sprite.pixelate,
        'Player atlas contains eight exact 8x8 frames with nearest sampling'
    )
    scene.ui.timeScale = 0
    frame = state.sprite.atlasFrame
    advance(scene, 4)
    tester:check(
        state.sprite.atlasFrame == frame,
        'World2D pause freezes player flipbook animation'
    )
    scene:release()
    local package =
        require('source.engine.scenes.package').open('source/game/scenes/abilityRunner2D')
    local host = require('source.engine.scenes.host').new(tester.manager, package, {})
    host:load()
    advance(host, 50)
    host:keypressed('space')
    advance(host, 2)
    local _, velocity = host.state.player.body:getLinearVelocity()
    tester:check(
        velocity > 200,
        'The portable runner responds to keyboard actions in the minimal game host'
    )
    host:draw()
    host:release()
end

function Tests.run(tester)
    Tests.layers(tester)
    Tests.scenes(tester)
end

return Tests
