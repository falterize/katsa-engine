local Tests = {}
function Tests.run(tester)
    local files = {}
    local fs = {
        createDirectory = function()
            return true
        end,
        read = function(path)
            return files[path]
        end,
        write = function(path, text)
            files[path] = text
            return true
        end,
    }
    for index = 1, 12 do
        require('source.engine.debug.crashHistory').write(fs, 'Crash ' .. index)
    end
    tester:check(
        files['crashes/crash-01.txt']:match('Crash 12$')
            and files['crashes/crash-10.txt']:match('Crash 3$')
            and files['crashes/crash-11.txt'] == nil,
        'Crash history retains exactly the latest ten reports in order'
    )
    local world, ui, physics, body, release = tester:environment()
    tester:check(
        ui.particles == nil and ui.environment.particles.maxParticles == 4096,
        'Particle settings exist without creating a runtime particle system'
    )
    ui.environment.particles.maxParticles = 2048
    body(100, 0, 'Static', { shape = 'Box', size = { 200, 10 } })
    local e = ui:create('ParticleEmitter2D', {
        name = 'ParticleProbe2D',
        position = { 100, 50 },
        rate = 0,
        direction = { 0, -1 },
        spread = 0,
        speed = { 100, 100 },
        lifetime = { 5, 5 },
        startSize = { 10, 10 },
        collisionEnabled = true,
        offscreenBehavior = 'Simulate',
    })
    tester:check(
        ui.particles.maxParticles == 2048 and ui.particles.settings == ui.environment.particles,
        'Particle system adopts the existing Environment settings table'
    )
    tester:check(
        e:isA('Node2D') and e:emit(3) == 3,
        'ParticleEmitter2D uses spatial hierarchy and the common emission pool'
    )
    for _ = 1, 40 do
        ui:updatePhysics(1 / 60)
    end
    tester:check(
        e.liveCount == 3
            and e.particles[1].y >= 5
            and ui.particles.stats.collisionQueries <= ui.particles.collisionBudget,
        '2D particles sweep against Box2D geometry with the shared query budget'
    )
    local age = e.particles[1].age
    ui.timeScale = 0
    ui:updatePhysics(1)
    ui.timeScale = 1
    tester:check(e.particles[1].age == age, 'World2D time scale pauses its particle simulation')
    for _, mode in ipairs({ 'Decal', 'Texture', 'Tiles', 'Atlas', 'XML' }) do
        e.imageMode = mode
        if mode == 'XML' then
            e.xml = 'source/game/scenes/abilityRunner2D/assets/animations/player.xml'
            e.texture = 'source/game/scenes/abilityRunner2D/assets/textures/player.png'
        end
        ui:draw()
        tester:check(
            ui.particles.stats.rendered > 0,
            '2D particles draw with shared ' .. mode .. ' image mode'
        )
    end
    e.enabled = false
    e.disabledBehavior = 'Clear'
    ui:updatePhysics(1 / 60)
    tester:check(
        e.liveCount == 0 and #e.pool >= 3,
        'Disabled 2D emitters clear into their reusable pool'
    )
    local tree = require('source.engine.editor.tree.traversal')
    local found, particles = false, false
    for _, row in ipairs(tree.children(ui.environment)) do
        if row.name == 'Debug' then
            for _, child in ipairs(tree.children(row)) do
                if child.name == 'Physics2D' then
                    found = child._editorTarget == physics.debug
                end
            end
        elseif row.name == 'Particles2D' then
            particles = row._editorTarget == ui.particles.settings
        end
    end
    tester:check(found and particles, 'Environment owns shared 2D debug and particle Settings')
    tester:check(
        ui.environment.className == 'Environment'
            and world.environment.className == 'Environment'
            and world.environment:isA('EnvironmentLighting'),
        'Both dimensions create a canonical Environment with legacy class compatibility'
    )
    tester:check(not pcall(function()
        ui.environment:destroy()
    end), 'Required Environment cannot be deleted independently')
    tester:check(not pcall(function()
        ui:create('Environment', {}, ui)
    end), 'World2D rejects duplicate Environment nodes')
    local camera = ui:create('Camera2D', {})
    tester:check(
        ui.currentCamera == camera and ui.camera2D == camera,
        'World2D currentCamera preserves the legacy camera2D alias'
    )
    camera:destroy()
    tester:check(ui.currentCamera == nil, 'Camera destruction clears currentCamera')
    release()
    local Application = require('source.game.runtime.application')
    local platformScene = Application.new(tester.manager, 'physics2D')
    platformScene:load()
    local locked, free =
        platformScene.demo.platformParticles[1], platformScene.demo.platformParticles[2]
    tester:check(
        locked.parent:isA('Attachment2D')
            and free.parent:isA('Attachment2D')
            and locked.parent.position[1] == -free.parent.position[1],
        'Rotating platform emitters use attachments at opposite platform ends'
    )
    locked:emit(1)
    free:emit(1)
    local lp, fp = locked.particles[1], free.particles[1]
    local math3d = require('source.engine.math.math3d')
    local beforeX, beforeY = math3d.transform(locked:getWorldMatrix(), lp.x, lp.y, 0)
    local freeX, freeY = fp.x, fp.y
    platformScene.demo.motorArm.body:teleport(1080, -440, 90)
    local afterX, afterY = math3d.transform(locked:getWorldMatrix(), lp.x, lp.y, 0)
    tester:check(
        lp.space == 'Local' and (beforeX - afterX) ^ 2 + (beforeY - afterY) ^ 2 > 100,
        'Local particles follow attachment rotation while retaining their local position'
    )
    tester:check(
        fp.space == 'World' and fp.x == freeX and fp.y == freeY,
        'World particles remain behind when the attached platform rotates'
    )
    platformScene:release()
    local scene = Application.new(tester.manager, 'uiGallery')
    scene:load()
    tester:check(
        scene.demo.textBox:isA('TextBox') and scene.demo.multilineTextBox.multiline,
        'UI Gallery includes single-line and multiline TextBox examples'
    )
    scene.demo.root.visible = false
    for _, key in ipairs({ 'billboardTextBox', 'surfaceTextBox' }) do
        local box = scene.demo[key]
        local board = box.ui.owner
        board.visible = true
        if key == 'surfaceTextBox' then
            board.parent.visible = true
        end
        scene:draw()
        box.ui:layout()
        local bounds = board.bounds
        local x = (box._x + box._width / 2 - bounds[1]) / (bounds[3] - bounds[1]) - 0.5
        local y = 0.5 - (box._y + box._height / 2 - bounds[2]) / (bounds[4] - bounds[2])
        local wx, wy, wz = require('source.engine.math.math3d').transform(board.matrix, x, y, 0)
        local sx, sy = scene.camera:project({ wx, wy, wz })
        scene:pointerpressed('mouse', sx, sy)
        local focused = require('source.engine.ui.widgets.textFocus').current
        tester:check(focused == box, key .. ': projected world UI pointer focuses TextBox')
        box:focus(true)
        scene:textinput('Edited in world UI')
        tester:check(
            box.text == 'Edited in world UI',
            key .. ': keyboard routing edits world-space text'
        )
        scene:pointerreleased('mouse', sx, sy)
        box:blur()
        scene:draw()
    end
    scene.debugOverlay:setDebugSection('2D Physics')
    tester:check(
        scene.debugOverlay.debugSection == '2D Physics',
        'F4 exposes separate grouped debug sections'
    )
    local worldDebug = false
    for _, row in ipairs(tree.children(scene.world.environment)) do
        if row.name == 'Debug' then
            worldDebug = row._editorTarget == scene.world.environment.debug
        end
    end
    tester:check(worldDebug, 'World3D Environment owns categorized Debug Settings')
    scene:release()
    scene = Application.new(tester.manager, 'particles')
    scene:load()
    local host = scene.world:create(
        'Mesh3D',
        { name = 'ImageModeDecalHost', position = { 0, 20, 80 }, size = { 20, 20, 1 } }
    )
    local decal = scene.world:create('Decal3D', {
        name = 'ImageModeDecal',
        image = 'source/game/scenes/abilityRunner2D/assets/textures/player.png',
    }, host)
    for _, mode in ipairs({ 'Decal', 'Texture', 'Tiles', 'Atlas', 'XML' }) do
        decal.imageMode = mode
        decal.xml = 'source/game/scenes/abilityRunner2D/assets/animations/player.xml'
        decal:update(scene.world, scene.camera)
        scene:draw()
        tester:check(
            decal.mode == mode and decal.textureImage ~= nil,
            'Decal3D supports shared ' .. mode .. ' image mode'
        )
    end

    scene.demo.emitter.simulationSpace = 'Local'
    scene.demo.emitter:emit(1)
    tester:check(
        scene.demo.emitter.particles[#scene.demo.emitter.particles].space == 'Local',
        'ParticleEmitter3D exposes the same Local locked-particle setting'
    )
    scene.demo.emitter.simulationSpace = 'World'
    for _, mode in ipairs({ 'Tiles', 'XML' }) do
        local emitter = scene.demo.emitter
        emitter.imageMode = mode
        if mode == 'XML' then
            emitter.xml = 'source/game/scenes/abilityRunner2D/assets/animations/player.xml'
            emitter.texture = 'source/game/scenes/abilityRunner2D/assets/textures/player.png'
        end
        emitter:emit(5)
        scene:update(1 / 30, 1 / 30)
        scene:draw()
        tester:check(
            #emitter.particles > 0,
            'Shared simulation preserves 3D particles with ' .. mode .. ' image mode'
        )
    end
    scene:release()
end
return Tests
