-- Post-processing: every effect changes the image the way its name says, settings changes
-- rebuild reused frames, and the inspector lists the Godot-style sections.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Renderer = require('source.engine.graphics.pipeline.renderer')
local Schema = require('source.engine.editor.inspectors.schema')

local Tests = {}

local WIDTH, HEIGHT = 320, 180

local function luma(image, x, y)
    local r, g, b = image:getPixel(x, y)
    return (r + g + b) / 3, r, g, b
end

-- A floor, a box standing on it, and a far bright wall.
local function build()
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.sky.enabled, settings.fog.enabled, settings.gizmos.enabled = false, false, false
    settings.ambient = { 90, 90, 90 }
    settings.shadows.enabled = false
    local world = World3D.new(resources, settings)
    world:create('DirectionalLight3D', { name = 'Sun', direction = { 0.4, -1, 0.2 }, castShadow = false })
    local camera = world:addCamera({
        position = { 0, 60, -60 },
        rotation = { -22, 0, 0 },
        drawDistance = 2000,
    })
    world:create('Mesh3D', {
        name = 'Floor',
        position = { 0, -2, 150 },
        size = { 600, 4, 600 },
        color = { 0.7, 0.7, 0.7, 1 },
    })
    world:create('Mesh3D', {
        name = 'Box',
        position = { 0, 10, 40 },
        size = { 20, 20, 20 },
        color = { 0.8, 0.3, 0.2, 1 },
    })
    world:create('Mesh3D', {
        name = 'Wall',
        position = { 0, 30, 380 },
        size = { 40, 60, 4 },
        color = { 1, 1, 1, 1 },
    })
    local renderer = Renderer.new(resources)
    renderer.targetWidth, renderer.targetHeight = WIDTH, HEIGHT
    local e = world.environment
    e.render.msaa, e.render.renderDensity = 0, 1
    return world, camera, renderer, e
end

function Tests.run(tester)
    local world, camera, renderer, e = build()
    local function shot()
        return renderer:draw(world, camera, 0, true):newImageData()
    end
    local base = shot()

    -- Glow with nothing above its threshold leaves the image unchanged (Softlight is neutral).
    e.glow.enabled, e.glow.hdrThreshold, e.glow.intensity = true, 4, 1
    local quiet = shot()
    tester:check(
        math.abs(luma(quiet, WIDTH / 2, HEIGHT / 2) - luma(base, WIDTH / 2, HEIGHT / 2)) < 0.01
            and math.abs(luma(quiet, WIDTH / 2, HEIGHT - 2) - luma(base, WIDTH / 2, HEIGHT - 2))
                < 0.01,
        'Glow without bright pixels does not darken the image'
    )
    e.glow.enabled, e.glow.hdrThreshold, e.glow.intensity = false, 0.8, 0.8

    e.fog.enabled, e.fog.volumetric, e.fog.density, e.fog.volumetricDistance =
        true, true, 0.01, 300
    local fogged = shot()
    tester:check(
        math.abs(luma(fogged, WIDTH / 2, HEIGHT - 2) - luma(base, WIDTH / 2, HEIGHT - 2)) > 0.02
            and Schema.visible(e.fog, 'anisotropy'),
        'Volumetric fog hazes the scene and shows its settings in the Fog section'
    )
    e.fog.volumetric = false
    tester:check(not Schema.visible(e.fog, 'anisotropy'), 'Fog hides volumetric settings when it is off')
    e.fog.enabled = false

    e.adjustments.enabled, e.adjustments.saturation = true, 0
    local grey = shot()
    local _, r, g, b = luma(grey, WIDTH / 2, HEIGHT * 0.6)
    tester:check(math.abs(r - g) < 0.01 and math.abs(g - b) < 0.01, 'Saturation 0 gives greyscale')
    e.adjustments.saturation, e.adjustments.brightness = 1, 0.5
    local dark = shot()
    tester:check(
        luma(dark, WIDTH / 2, HEIGHT * 0.6) < luma(base, WIDTH / 2, HEIGHT * 0.6) * 0.7,
        'Brightness below 1 darkens the image'
    )
    e.adjustments.enabled, e.adjustments.brightness = false, 1

    -- Pixel just outside the bright far wall's right edge.
    local sx, sy = camera:project({ 20, 30, 380 })
    local probeX, probeY = math.floor(sx) + 3, math.floor(sy)
    e.glow.enabled, e.glow.blendMode, e.glow.intensity, e.glow.hdrThreshold =
        true, 'Additive', 2, 0.3
    local glow = shot()
    tester:check(
        luma(glow, probeX, probeY) > luma(base, probeX, probeY) + 0.02,
        'Glow spreads light beyond a bright edge'
    )
    e.glow.enabled = false

    -- Floor patch right in front of the box foot.
    local function patch(image)
        local sum, count = 0, 0
        for x = -8, 8, 2 do
            for z = 28, 32, 2 do
                local px, py = camera:project({ x, 0, z })
                if px then
                    sum = sum + luma(image, math.floor(px), math.floor(py))
                    count = count + 1
                end
            end
        end
        return sum / count
    end
    e.ssao.enabled, e.ssao.radius, e.ssao.intensity = true, 12, 3
    local occluded = shot()
    tester:check(patch(occluded) < patch(base) * 0.93, 'SSAO darkens the floor at the box foot')
    e.ssao.enabled = false

    local function sharpness(image)
        local peak = 0
        for x = math.floor(sx) - 25, math.floor(sx) + 25 do
            peak = math.max(peak, math.abs(luma(image, x + 1, probeY) - luma(image, x, probeY)))
        end
        return peak
    end
    e.depthOfField.enabled, e.depthOfField.farDistance, e.depthOfField.farTransition =
        true, 100, 50
    e.depthOfField.amount = 0.5
    local blurred = shot()
    tester:check(
        sharpness(blurred) < sharpness(base) * 0.6,
        'Far depth of field softens the distant wall edge'
    )
    tester:check(
        math.abs(luma(blurred, WIDTH / 2, HEIGHT * 0.9) - luma(base, WIDTH / 2, HEIGHT * 0.9)) < 0.05,
        'Depth of field keeps near geometry sharp'
    )
    e.depthOfField.enabled = false

    e.render.screenSpaceAA = 'FXAA'
    local smooth = shot()
    local differs = 0
    for y = 0, HEIGHT - 1, 2 do
        for x = 0, WIDTH - 1, 2 do
            if math.abs(luma(smooth, x, y) - luma(base, x, y)) > 0.02 then
                differs = differs + 1
            end
        end
    end
    tester:check(differs > 10, 'FXAA filters edges')
    e.render.screenSpaceAA = 'Disabled'

    local clean = shot()
    tester:check(
        math.abs(luma(clean, WIDTH / 2, HEIGHT / 2) - luma(base, WIDTH / 2, HEIGHT / 2)) < 0.001
            and math.abs(luma(clean, 1, 1) - luma(base, 1, 1)) < 0.001,
        'Turning every effect off restores the plain image'
    )

    -- A reused frame must pick up a changed setting.
    local before = luma(shot(), WIDTH / 2, HEIGHT / 2)
    e.adjustments.enabled, e.adjustments.brightness = true, 0.3
    tester:check(
        luma(shot(), WIDTH / 2, HEIGHT / 2) < before * 0.7,
        'A setting change rebuilds a reused frame'
    )

    tester:check(
        Schema.keys(e.glow, {})[5] == 'blendMode'
            and #Schema.options(e.glow, 'blendMode') == 5
            and not Schema.visible(e.glow, 'mix')
            and Schema.options(e.render, 'screenSpaceAA')[2] == 'FXAA',
        'The inspector lists the Godot-style Glow and anti-aliasing options'
    )
end

return Tests
