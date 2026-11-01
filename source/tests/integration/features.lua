local engine = require('source.engine')

local function close(a, b)
    return math.abs(a - b) < 0.002
end
return function(test, scene)
    local function press(name)
        local node = assert(scene.buttons[name])
        if node.parent == scene.toolsPanel then
            scene.toolsPanel.visible = true
        end
        scene.ui:layout()
        if node.parent == scene.toolsPanel then
            scene.toolsPanel.scrollY = math.max(0, node._y - scene.toolsPanel._y - 20)
            scene.ui:layout()
        end
        local x, y = scene.ui:position(node)
        x = scene.ui.offsetX + (x + node._width / 2) * scene.ui.scale
        y = scene.ui.offsetY + (y + node._height / 2) * scene.ui.scale
        scene.input:press('feature-button', x, y)
        test:check(scene.input.cameraId == nil, name .. ' button captures input before camera')
        scene.input:release('feature-button')
    end
    press('boards')
    scene.renderer:prepare(scene.world, scene.camera, scene.time)
    test:check(#scene.renderer.top == 0, 'Billboards OFF removes all visible panels')
    press('boards')
    scene.renderer:prepare(scene.world, scene.camera, scene.time)
    test:check(#scene.renderer.top > 0, 'Billboards ON restores panels')
    scene.toolsPanel.visible = false
    local board = scene.boards.fixed
    test:check(
        board.canvas:getPixelWidth() >= board.resolvedCanvasSize[1] * 2,
        'BillboardUI uses at least 2x physical resolution'
    )
    local canvas = board.canvas
    board.subtitle.text = 'Direct text edit'
    scene.renderer:prepare(scene.world, scene.camera, scene.time)
    test:check(
        board.uiRevision == board.ui.revision and board.canvas == canvas,
        'Direct UI text edit refreshes and reuses billboard canvas'
    )
    board.subtitle.text = 'Constant screen size'
    press('motion')
    local z = board.position[3]
    scene:update(0.05, 0.05)
    test:check(board.position[3] == z, 'Motion OFF stops moving billboards')
    press('motion')
    press('music')
    local music = scene.musicVoice
    test:check(
        music:isPlaying() and music.source:getChannelCount() == 2,
        'Music button starts a stereo stream'
    )
    press('music')
    test:check(music.manualPause and not music:isPlaying(), 'Music button pauses playback')
    press('music')
    test:check(music:isPlaying(), 'Music button resumes the existing stream')
    press('mixer')
    local slider = scene.groupSliders.music
    local x, y = scene.ui:position(slider)
    local sx, sy =
        scene.ui.offsetX + (x + 12) * scene.ui.scale, scene.ui.offsetY + (y + 24) * scene.ui.scale
    scene.input:press('slider', sx, sy)
    scene.input:move('slider', sx + (slider._width - 24) * 0.25 * scene.ui.scale, sy, 10, 0)
    test:check(
        close(scene.audio:getGroupVolume('music'), 0.25) and scene.input.cameraId == nil,
        'Mixer slider drags with captured touch and adjusts only music group'
    )
    scene.input:release('slider')
    scene.mixerOverlay.visible = false
    scene.audio:setGroupVolume('music', 0.7)
    scene.audio:addGroup('dialogue', { parent = 'effects', volume = 0.5 })
    test:check(
        close(scene.audio:groupGain('dialogue'), 0.85 * 0.8 * 0.5),
        'Nested sound groups multiply parent and master gains'
    )
    local emitter = { position = { 0, 0, 0 } }
    local voice = scene.audio:play('assets/audio/effects/stereoChime.wav', {
        object = emitter,
        minDistance = 10,
        maxDistance = 100,
        rolloff = 'Linear',
        loop = true,
    })
    scene.audio:update({ position = { 0, 0, 0 }, forward = { 0, 0, 1 }, up = { 0, 1, 0 } })
    test:check(
        #voice.sources == 2
            and voice.sources[1]:getChannelCount() == 1
            and voice.sources[2]:getChannelCount() == 1,
        'Spatial stereo preserves both channels as positioned emitters'
    )
    local full = voice.gain
    emitter.position[3] = 55
    scene.audio:update()
    test:check(
        close(voice.gain, full * 0.5),
        'Spatial linear falloff reaches half volume between min and max'
    )
    local _, _, audioZ = voice.source:getPosition()
    test:check(audioZ == -55, 'Spatial coordinates mirror Z for correct camera left and right')
    emitter.position[3] = 100
    scene.audio:update()
    test:check(
        voice.gain == 0 and voice.source:getVolume() == 0,
        'Spatial audio is silent at maximum distance'
    )
    emitter.position[3] = 5
    scene.audio:update()
    test:check(close(voice.gain, full), 'Spatial audio has full volume inside minimum distance')
    press('time')
    local elapsed = scene.time
    local startZ = scene.camera.position[3]
    scene.input.axisY = 1
    scene.manager:update(0.2)
    scene.input.axisY = 0
    test:check(
        close(scene.time - elapsed, 0.1)
            and close(scene.camera.position[3] - startZ, scene.controls.speed * 0.1),
        'Half time slows game clock and player movement together'
    )
    test:check(
        close(music.source:getPitch(), 0.5) and close(voice.source:getPitch(), 0.5),
        'Half time slows music and spatial sound pitch'
    )
    press('time')
    elapsed = scene.time
    scene.manager:update(0.2)
    test:check(
        scene.time == elapsed and not music:isPlaying(),
        'Zero time freezes simulation and pauses scaled sound'
    )
    local uiVoice =
        scene.audio:play('assets/audio/effects/click.wav', { group = 'ui', timeScaled = false })
    test:check(
        uiVoice:isPlaying() and close(uiVoice.source:getPitch(), 1),
        'UI feedback remains audible at zero time'
    )
    press('time')
    scene.audio:update(scene.camera)
    test:check(
        music:isPlaying() and close(music.source:getPitch(), 1),
        'Normal time resumes frozen audio'
    )
    voice:stop()
    scene.audio:update(scene.camera)
    test:check(voice.released, 'Stopped voices release all channel sources')
    music:pause()
    scene.camera.position = { 0, 0, 0 }
    scene.camera.rotation = { 0, 0, 0 }
    press('effects')
    scene.renderer:draw(scene.world, scene.camera, scene.time)
    test:check(
        scene.effectTarget.material == scene.objectEffect
            and scene.buttons.effects.material == scene.uiEffect,
        'Shader button assigns object and UI materials'
    )
    test:check(
        katsa.graphics.validateShader(true, scene.objectEffect.code),
        'Custom vertex and fragment material compiles as GLES'
    )
    press('effects')
    test:check(
        scene.effectTarget.material == nil and scene.buttons.effects.material == nil,
        'Shader button restores default materials'
    )
    local clock = engine.time.new()
    clock:setScale(0.5)
    local physics = katsa.physics.newWorld(0, 0, true)
    local body = katsa.physics.newBody(physics, 0, 0, 'dynamic')
    local shape = katsa.physics.newCircleShape(1)
    local fixture = katsa.physics.newFixture(body, shape)
    body:setLinearVelocity(10, 0)
    clock:physicsStep(physics, 0.2)
    test:check(close(body:getX(), 1), 'time helper advances an actual physics body by scaled delta')
    physics:destroy()
    local scope = scene.audio:scope()
    local scoped = scope:play('assets/audio/effects/click.wav', { group = 'ui', loop = true })
    scope:release()
    test:check(
        scoped.released and scene.audio:getGroupVolume('music') == 0.7,
        'Audio scope cleanup releases voices while preserving mixer settings'
    )
    scene.toolsPanel.visible = false
end
