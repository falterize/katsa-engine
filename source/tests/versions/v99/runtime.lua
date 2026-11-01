local T = {}

local function extra(test)
    local Opacity = require('source.engine.materials.opacity')
    local encoded = love.filesystem.newFileData('assets/textures/surfaces/dirt.jpg')
    local pixels = love.image.newImageData(encoded)
    local image = love.graphics.newImage(pixels)
    Opacity.register(image, pixels)
    local reference = Opacity.image(image)
    Opacity.register(image, pixels, encoded)
    test:check(
        reference and Opacity.image(image),
        'Decoded JPEG classification agrees with exact pixel scanning'
    )
    image:release()
    pixels:release()
    encoded:release()
    local alpha = love.image.newImageData(2, 2, 'rgba8')
    local png = alpha:encode('png')
    local disguised = love.filesystem.newFileData(png:getString(), 'alpha.jpg')
    local decoded = love.image.newImageData(disguised)
    local transparent = love.graphics.newImage(decoded)
    Opacity.register(transparent, decoded, disguised)
    test:check(
        not Opacity.image(transparent),
        'A transparent PNG named JPEG retains alpha scanning'
    )
    transparent:release()
    decoded:release()
    disguised:release()
    png:release()
    alpha:release()
    local key = love.filesystem.newFileData('source/tests/fixtures/alphaColorKey.png')
    local keyed = love.image.newImageData(key)
    local keyedImage = love.graphics.newImage(keyed)
    Opacity.register(keyedImage, keyed, key)
    test:check(
        not Opacity.image(keyedImage),
        'RGB PNG color-key transparency retains exact scanning'
    )
    keyedImage:release()
    keyed:release()
    key:release()
    local original = love.image.newImageData('assets/sources/textures/sky/dayCross-original.png')
    local optimized = love.image.newImageData('assets/textures/sky/dayCross.png')
    test:check(
        original:getFormat() == optimized:getFormat()
            and original:getString() == optimized:getString(),
        'Lossless RGB sky decodes to byte-identical native RGBA pixels'
    )
    original:release()
    optimized:release()
    local Resources = require('source.engine.core.resources')
    local Renderer = require('source.engine.graphics.pipeline.renderer')
    local scope = Resources.new()
    local renderer = Renderer.new(scope)
    test:check(
        rawget(renderer, 'shader') == nil
            and rawget(renderer, 'wireShader') == nil
            and rawget(renderer.shadows, 'shader') == nil,
        'Unused renderer programs are not compiled during construction'
    )
    local general, wire, shadow = renderer.shader, renderer.wireShader, renderer.shadows.shader
    test:check(
        general == renderer.shader
            and wire == renderer.wireShader
            and shadow == renderer.shadows.shader,
        'Public shader fields compile on first access and return the same owned programs'
    )
    renderer:release()
    scope:release()
    scope = Resources.new()
    renderer = Renderer.new(scope)
    local shadows = renderer.shadows
    renderer:release()
    scope:release()
    local disposed = renderer.shader == nil and renderer.wireShader == nil and shadows.shader == nil
    scope = Resources.new()
    renderer = Renderer.new(scope)
    shadows = renderer.shadows
    scope:release()
    test:check(
        disposed and renderer.shader == nil and renderer.wireShader == nil and shadows.shader == nil,
        'Released renderers or resource scopes cannot allocate previously unused programs'
    )
    renderer:release()
    local scene = assert(test.manager:switch(require('source.game.runtime.game').new, 'combined'))
    scene.world.debug.wireframe = true
    test.manager:update(1 / 60)
    test.manager:draw()
    test:check(
        rawget(scene.renderer, 'wireShader') ~= nil and rawget(scene.renderer, 'shader') == nil,
        'First wireframe draw creates its shader without forcing the general program'
    )
    scene.world.debug.wireframe = false
    scene.renderer.forceGeneralShader = true
    scene.renderer:invalidate()
    test.manager:draw()
    test:check(
        rawget(scene.renderer, 'shader') ~= nil,
        'Forced general shading remains available after wireframe'
    )
end

function T.new(manager)
    local base = require('source.tests.versions.v98.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v99 regression/integration checks')
    end
    return base
end

return T
