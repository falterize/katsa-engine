-- Native audio and GPU checks, only run under LÖVE.
return function(test)
    local Node = require('source.engine.nodes')
    local Audio = require('source.engine.audio')
    local audio = Audio.new()
    local root = Node.new('World3D', {})
    local world = { audio = audio, root = root }
    root._world = world
    local group = Node.create('SoundGroup', { volume = 0.5 }, root, world)
    local sound = Node.create(
        'Sound',
        { resource = 'assets/audio/effects/effectProbe.wav', looped = true, volume = 0.6 },
        group,
        world
    )
    local effect = Node.create('SoundReverb', { decaytime = 2 }, sound, world)
    sound:play()
    sound:pause()
    sound:seek(0.25)
    test:check(math.abs(sound:tell() - 0.25) < 0.02, 'Native Sound seek/tell uses seconds')
    test:check(
        math.abs(sound._voice.source:getVolume() - 0.255) < 0.0001,
        'Native SoundGroup updates source gain'
    )
    if katsa.audio.isEffectsSupported() and katsa.audio.getMaxSourceEffects() > 0 then
        test:check(
            effect.status == 'Applied',
            'Native reverb is defined and attached on supported device'
        )
    else
        test:check(
            effect.status == 'Unsupported on this device'
                or effect.status == 'Source effect limit reached',
            'Native effects fallback reports device limits'
        )
    end
    sound:play()
    audio:pause()
    audio:resume()
    root:destroy()
    audio:release()
    test:check(
        #audio.nodes == 0 and #audio.effects == 0,
        'Native node scene cleanup removes audio registrations'
    )
    local Resources = require('source.engine.core.resources')
    local UI = require('source.engine.ui')
    local resources = Resources.new(require('source.game.data.manifest'))
    local ui = UI.new(64, 64, resources)
    local label = ui:create(
        'Frame',
        { x = 8, y = 8, width = 48, height = 48, color = { 1, 1, 1, 1 } },
        ui.content
    )
    ui:create('UICorner', { cornerRadius = 12 }, label)
    ui:create('UIGradient', {
        colorStops = {
            { time = 0, color = { 1, 0, 0, 1 } },
            { time = 1, color = { 0, 0, 1, 1 } },
        },
    }, label)
    ui:create('UIStroke', { target = 'Border', thickness = 2, color = { 1, 1, 1, 1 } }, label)
    local code = katsa.filesystem.read('assets/shaders/engine/uiGradient.glsl')
    local valid, message = katsa.graphics.validateShader(true, code, code)
    test:check(valid, 'Native GLES gradient shader validation: ' .. tostring(message))
    local canvas = katsa.graphics.newCanvas(64, 64)
    local g = katsa.graphics
    g.push('all')
    g.setCanvas({ canvas, stencil = true })
    g.origin()
    g.clear(0, 1, 0, 1)
    ui:draw()
    g.setCanvas()
    g.pop()
    local pixels = canvas:newImageData()
    local left, _, leftBlue = pixels:getPixel(14, 32)
    local right, _, rightBlue = pixels:getPixel(50, 32)
    test:check(
        left > leftBlue and rightBlue > right,
        'Native gradient interpolates across the full UI element'
    )
    local _, green = pixels:getPixel(8, 8)
    test:check(green > 0.95, 'Native rounded modifier clips gradient at the corner')
    local r, _, b = pixels:getPixel(9, 32)
    test:check(r > 0.8 and b > 0.8, 'Native border stroke renders separately over gradient')
    pixels:release()
    canvas:release()
    ui:release()
    resources:release()
end
