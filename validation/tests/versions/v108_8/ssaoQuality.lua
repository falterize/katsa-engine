-- SSAO: soft strength curve and the depth-aware upsample of the half-resolution occlusion.
-- KATSA_SSAOSHOT=<dir> also saves the frames (save directory) for a visual check.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Renderer = require('source.engine.graphics.pipeline.renderer')

local Module = {}

local WIDTH, HEIGHT = 320, 180

local function build(ssao)
    local resources = Resources.new(require('validation.tests.fixtures.manifest'))
    local settings = require('source.runtime.settings').create()
    settings.gizmos.enabled, settings.shadows.enabled = false, false
    local world = World3D.new(resources, settings)
    local camera = world:addCamera({ position = { 0, 1.3, 0 }, rotation = { 0, 0, 0 }, drawDistance = 400 })
    world:create('Mesh3D', { name = 'Floor', position = { 0, -2, 40 }, size = { 200, 4, 200 }, color = { 0.8, 0.8, 0.8, 1 } })
    world:create('Mesh3D', { name = 'Wall', position = { 0, 10, 14 }, size = { 60, 20, 2 }, color = { 0.8, 0.8, 0.8, 1 } })
    world:create('Mesh3D', { name = 'Near', position = { 6, 1.5, 8 }, size = { 3, 3, 3 }, color = { 0.8, 0.8, 0.8, 1 } })
    local environment = world.environment
    environment.sky.enabled, environment.fog.enabled = false, false
    environment.ambient = { 255, 255, 255 }
    environment.render.msaa, environment.render.renderDensity = 0, 1
    environment.ssao.enabled = ssao ~= false
    environment.ssao.radius, environment.ssao.quality = 2, 'High'
    local renderer = Renderer.new(resources)
    renderer.targetWidth, renderer.targetHeight = WIDTH, HEIGHT
    return world, camera, renderer
end

local function render(world, camera, renderer, tag)
    local clock = (renderer._probeClock or 0) + 1
    renderer._probeClock = clock
    local image = renderer:draw(world, camera, clock, true):newImageData()
    local dir = os.getenv('KATSA_SSAOSHOT')
    if dir and tag then
        image:encode('png', dir .. '/' .. tag .. '.png')
    end
    return image
end

local function luminance(image, x, y)
    local r, g, b = image:getPixel(x, y)
    return (r + g + b) / 3
end

function Module.run(self)
    local world, camera, renderer = build(true)
    for _, pitch in ipairs({ 0, 5, 12 }) do
        camera.rotation = { pitch, 0, 0 }
        render(world, camera, renderer)
        render(world, camera, renderer, 'ssao' .. pitch)
    end
    local apply = assert(katsa.filesystem.read('assets/shaders/engine/post/ssaoApply.glsl'))
    self:check(
        apply:find('snapToDepthTexel(tap)', 1, true) ~= nil and apply:find('smoothstep(0.0, tolerance, gap)', 1, true) ~= nil,
        'The apply pass upsamples the half-resolution occlusion with depth-similarity weights'
    )
    camera.rotation = { 12, 0, 0 }
    local lit = render(world, camera, renderer)

    -- The strength curve never clips: raising intensity darkens, but a lightly occluded pixel does
    -- not turn black.
    local environment = world.environment.ssao
    environment.intensity = 6
    local strong = render(world, camera, renderer, 'intensity6')
    local darkest = 1
    for y = 0, HEIGHT - 1, 2 do
        for x = 0, WIDTH - 1, 2 do
            darkest = math.min(darkest, luminance(strong, x, y))
        end
    end
    self:check(darkest > 0.02, ('A high intensity does not clip occlusion to black (darkest %.3f)'):format(darkest))
    environment.intensity = 1
    local weak = render(world, camera, renderer)
    environment.intensity = 2
    local mid = render(world, camera, renderer)
    local sumWeak, sumMid, sumStrong = 0, 0, 0
    for y = 0, HEIGHT - 1, 2 do
        for x = 0, WIDTH - 1, 2 do
            sumWeak = sumWeak + luminance(weak, x, y)
            sumMid = sumMid + luminance(mid, x, y)
            sumStrong = sumStrong + luminance(strong, x, y)
        end
    end
    self:check(sumWeak > sumMid and sumMid > sumStrong, 'Intensity darkens monotonically')
    self:check(lit ~= nil, 'SSAO frames render')
end

return Module
