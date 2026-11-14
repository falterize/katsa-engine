-- shader_type sky and fog: Shader3D nodes that replace the background and reshape volumetric fog.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Renderer = require('source.engine.graphics.pipeline.renderer')

local Module = {}

local WIDTH, HEIGHT = 160, 90
local fixtures = 'validation/tests/fixtures/shaders/'

local function build()
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.gizmos.enabled, settings.shadows.enabled = false, false
    local world = World3D.new(resources, settings)
    local camera = world:addCamera({ position = { 0, 5, 0 }, rotation = { 0, 0, 0 }, drawDistance = 800 })
    world:create('Mesh3D', {
        name = 'Floor',
        position = { 0, -2, 200 },
        size = { 600, 4, 600 },
        color = { 0.7, 0.7, 0.7, 1 },
    })
    local renderer = Renderer.new(resources)
    renderer.targetWidth, renderer.targetHeight = WIDTH, HEIGHT
    world.environment.render.msaa, world.environment.render.renderDensity = 0, 1
    return world, camera, renderer
end

function Module.run(self)
    local world, camera, renderer = build()
    local clock = 0
    local function shot()
        clock = clock + 1
        return renderer:draw(world, camera, clock, true):newImageData()
    end
    local sky = world:create('Shader3D', {
        name = 'SunsetSky',
        shaderPath = fixtures .. 'sky.glsl',
        uniforms = { horizon = { 1, 0, 0 }, pulse = 0 },
    })
    local red = shot()
    local r, g, b = red:getPixel(WIDTH / 2, 40)
    self:check(r > 0.3 and r > g * 2 and r > b * 2, 'A sky shader paints the background')
    sky.shaderPath = fixtures .. 'skyPlain.glsl'
    local green = shot()
    local _, gg = green:getPixel(WIDTH / 2, 40)
    self:check(gg > 0.5, 'A sky shader that ignores SKY_COLOR still renders')
    sky.shaderPath = fixtures .. 'sky.glsl'
    sky.enabled = false
    local plain = shot()
    local pr, pg, pb = plain:getPixel(WIDTH / 2, 40)
    self:check(math.abs(pr - r) + math.abs(pg - g) + math.abs(pb - b) > 0.1, 'Disabling it restores the sky')
    self:check(
        #(world.shaderNodes or {}) == 1
            and require('source.engine.graphics.shaders.materialResolver').resolve(world, world.objects[1]) == nil,
        'Mesh shaders ignore sky and fog shaders'
    )

    local clear = shot()
    local fogEnvironment = world.environment.fog
    fogEnvironment.enabled, fogEnvironment.volumetric = true, true
    fogEnvironment.density, fogEnvironment.volumetricDistance = 0.2, 400
    local fogged = shot()
    local fog = world:create('Shader3D', {
        name = 'ClearFog',
        shaderPath = fixtures .. 'fog.glsl',
        uniforms = { strength = 0 },
    })
    local cleared = shot()
    local function floorLuma(image)
        local fr, fg, fb = image:getPixel(WIDTH / 2, 60)
        return (fr + fg + fb) / 3
    end
    self:check(
        math.abs(floorLuma(fogged) - floorLuma(clear)) > 0.01
            and math.abs(floorLuma(cleared) - floorLuma(clear)) < 0.01,
        'A fog shader reshapes the volumetric density (strength 0 clears the haze)'
    )
    fog.enabled = false
    fogEnvironment.enabled = false

    -- hint_screen_texture / hint_depth_texture: a glass pane that shows the scene behind it with
    -- red and blue swapped. The wall sits in the top half so a flipped lookup would be caught.
    world.environment.sky.enabled = false
    sky.enabled = false
    world:create('Mesh3D', {
        name = 'RedWall',
        position = { 0, 20, 60 },
        size = { 80, 20, 2 },
        color = { 0.9, 0.1, 0.1, 1 },
    })
    local before = shot()
    local pane = world:create('Mesh3D', {
        name = 'Glass',
        position = { 0, 5, 10 },
        size = { 80, 40, 1 },
        color = { 1, 1, 1, 1 },
    })
    world:create('Shader3D', {
        name = 'GlassShader',
        shaderPath = fixtures .. 'sceneTextures.glsl',
    }, pane)
    local after = shot()
    local br, bg, bb = before:getPixel(WIDTH / 2, 30)
    local ar, ag, ab = after:getPixel(WIDTH / 2, 30)
    self:check(
        br - bb > 0.1 and math.abs(ar - bb) < 0.05 and math.abs(ab - br) < 0.05,
        ('A hint_screen_texture sampler shows the scene behind the mesh (%.2f %.2f %.2f -> %.2f %.2f %.2f)')
            :format(br, bg, bb, ar, ag, ab)
    )
end

return Module
