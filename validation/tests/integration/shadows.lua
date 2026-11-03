local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Renderer = require('source.engine.graphics.pipeline.renderer')
local Material = require('source.engine.graphics.materials.material')
return function(test)
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.sky.enabled, settings.fog.enabled, settings.gizmos.enabled = false, false, false
    settings.ambient = { 8, 8, 8 }
    settings.sun.enabled, settings.sun.direction, settings.sun.brightness =
        true, { 0.4, -1, 0.2 }, 1
    settings.shadows.enabled, settings.shadows.resolution = true, 256
    -- Pixel/allocation tests intentionally request an unthrottled full atlas.
    settings.shadows.sourceFadeSeconds = 0
    settings.shadows.maxUpdateFaces = 195
    settings.shadows.visibleFacesOnly = false
    settings.shadows.filterSamples, settings.shadows.normalBias, settings.shadows.bias =
        1, 0.5, 0.02
    local world = World3D.new(resources, settings)
    local camera = world:addCamera({
        position = { 0, 85, -120 },
        rotation = { -28, 0, 0 },
        drawDistance = 1000,
    })
    local renderer = Renderer.new(resources)
    local ground = world:create('Mesh3D', {
        name = 'Ground',
        castShadow = false,
        position = { 0, -2, 50 },
        size = { 220, 4, 220 },
        texture = 'white',
    })
    local caster = world:create('Mesh3D', {
        name = 'Caster',
        position = { 0, 20, 45 },
        size = { 25, 40, 25 },
        texture = 'white',
        color = { 0.2, 0.4, 0.7, 1 },
    })

    local function image()
        renderer.shadows.nextUpdate = 0
        renderer:draw(world, camera, 0)
        return renderer.canvas:newImageData()
    end

    local function difference(a, b)
        local darker, total = 0, 0
        for y = 0, renderer.height - 1, 3 do
            for x = 0, renderer.width - 1, 3 do
                local r1 = a:getPixel(x, y)
                local r2 = b:getPixel(x, y)
                if r2 - r1 > 0.1 then
                    darker = darker + 1
                    total = total + r2 - r1
                end
            end
        end
        return darker, total
    end
    local withShadow = image()
    caster.castShadow = false
    local withoutShadow = image()
    local pixels = difference(withShadow, withoutShadow)
    print('SHADOW SUN PIXELS', pixels, renderer.shadows.drawCalls)
    test:check(pixels > 15, 'Directional shadow mapping darkens actual ground pixels')
    withShadow:encode('png', 'sunShadows-v41.png')
    test:check(
        renderer.shadows.sunTexelSizes[1] * 8 == renderer.shadows.sunTexelSizes[3],
        'Near sun cascade provides eight times the distant world-space texel detail'
    )
    local SunCascades = require('source.engine.graphics.shadows.sunCascades')
    local a, b = {}, {}
    local fixed = { position = { 0, 0, 0 } }
    local _, texel = SunCascades.prepare(fixed, { 0, -1, 0 }, 240, 256, 1, a)
    fixed.position[1] = texel * 0.2
    SunCascades.prepare(fixed, { 0, -1, 0 }, 240, 256, 1, b)
    test:check(
        math.abs(a[1] - b[1]) < 1e-8 and math.abs(a[3] - b[3]) < 1e-8,
        'Sub-texel camera motion preserves the sun map grid'
    )
    withShadow:release()
    withoutShadow:release()
    caster.castShadow = true
    ground.receiveShadow = false
    local noReceive = image()
    ground.receiveShadow = true
    local receive = image()
    test:check(
        difference(receive, noReceive) > 15,
        'Mesh3D.receiveShadow disables only receiving shadows'
    )
    noReceive:release()
    receive:release()
    settings.sun.enabled = false
    local light = world:create('SpotLight3D', {
        position = { 0, 95, 0 },
        rotation = { 60, 0, 0 },
        range = 250,
        radius = 210,
        brightness = 3,
        castShadow = true,
        forceUpdate = true,
    })
    renderer.lights.nextSelection = 0
    withShadow = image()
    caster.castShadow = false
    withoutShadow = image()
    pixels = difference(withShadow, withoutShadow)
    test:check(
        not renderer.shadows.sunEnabled and renderer.shadows.localLightCount > 0,
        'Local shadow mapping remains active with the sun disabled'
    )
    print('SHADOW SPOT PIXELS', pixels)
    test:check(pixels > 15, 'SpotLight3D shadows darken actual ground pixels')
    withShadow:release()
    withoutShadow:release()
    caster.castShadow = true
    light.type = 'PointLight3D'
    renderer.lights.nextSelection = 0
    withShadow = image()
    caster.castShadow = false
    withoutShadow = image()
    pixels = difference(withShadow, withoutShadow)
    print('SHADOW POINT PIXELS', pixels)
    test:check(
        pixels > 15 and renderer.shadows.assignments[1].kind == 1,
        'PointLight3D uses six depth faces and shadows actual pixels'
    )
    withShadow:release()
    withoutShadow:release()
    caster.castShadow = true
    caster.material = Material.new(resources, {
        vertexDeclarations = 'uniform float shift;',
        vertexCode = 'localPosition.x += shift;',
        uniforms = { shift = 0 },
    })
    withShadow = image()
    caster.material:set('shift', 4)
    withoutShadow = image()
    test:check(
        difference(withShadow, withoutShadow) > 15,
        'Custom vertex deformation changes shadow geometry'
    )
    withShadow:release()
    withoutShadow:release()
    settings.shadows.resolution = 128
    image():release()
    test:check(
        renderer.shadows.resolution == 128,
        'Changing shadow resolution recreates the depth atlas'
    )
    settings.shadows.filterSamples = 9
    image():release()
    test:check(renderer.shadows.generation > 5, 'Nine-sample filtered shadow shader renders')
    -- The receiver itself casts shadows: an empty floor must remain lit.
    caster.material, caster.castShadow, ground.castShadow = nil, false, true
    settings.shadows.enabled = true
    settings.shadows.sourceFadeSeconds = 0
    local clearFloor = image()
    settings.shadows.enabled = false
    local clearBaseline = image()
    test:check(
        difference(clearFloor, clearBaseline) == 0,
        'A self-shadowing floor stays lit without a blocker and without the sun'
    )
    clearFloor:release()
    clearBaseline:release()
    settings.shadows.enabled = true
    caster.castShadow = true
    local blocker = image()
    caster.castShadow = false
    local noBlocker = image()
    local changed, lit = 0, 0
    for y = 0, renderer.height - 1, 3 do
        for x = 0, renderer.width - 1, 3 do
            local r, g, b = noBlocker:getPixel(x, y)
            -- Count neutral floor pixels, excluding the blue caster and background.
            if math.abs(r - g) < 0.01 and math.abs(g - b) < 0.01 and r > 0.15 then
                lit = lit + 1
                local sr = blocker:getPixel(x, y)
                if r - sr > 0.1 then
                    changed = changed + 1
                end
            end
        end
    end
    test:check(
        changed > 15 and changed < lit * 0.2,
        'Local shadows darken a bounded floor region and preserve the surrounding illuminated floor'
    )
    local bluePixels, acnePixels = 0, 0
    for y = 0, renderer.height - 1 do
        for x = 0, renderer.width - 1 do
            local r, g, b = noBlocker:getPixel(x, y)
            if b - g > 0.03 and g - r > 0.02 then
                bluePixels = bluePixels + 1
                local _, _, shadowBlue = blocker:getPixel(x, y)
                if b - shadowBlue > 0.04 then
                    acnePixels = acnePixels + 1
                end
            end
        end
    end
    test:check(
        bluePixels > 100 and acnePixels < bluePixels * 0.05,
        'Slope-aware bias preserves the illuminated caster surface at low shadow resolution'
    )
    blocker:encode('png', 'localShadows-v41.png')
    blocker:release()
    noBlocker:release()
    settings.shadows.resolution = 64
    settings.lightSettings.maxActiveLights = 32
    settings.lightSettings.cullInvisible = false
    for i = 1, 31 do
        world:create('PointLight3D', {
            name = 'AtlasLight' .. i,
            position = { i - 16, 95, 0 },
            range = 250,
            brightness = 0.02,
            forceUpdate = true,
        })
    end
    renderer.lights.nextSelection = 0
    image():release()
    test:check(
        renderer.shadows.localLightCount == 32 and renderer.shadows.faceCount == 195,
        'All 32 PointLights receive six shadow faces without a single-light atlas budget'
    )
    light.enabled = false
    -- Keep selection cached to exercise compaction after a disabled light.
    renderer.lights.nextSelection = math.huge
    image():release()
    local valid = true
    for _, record in ipairs(renderer.shadows.assignments) do
        valid = valid and renderer.shadows.lightData[record.light.slot][1] == record.base
    end
    test:check(
        valid and renderer.shadows.localLightCount == 31,
        'Shadow slots follow packed GPU light slots after disabling a cached selected light'
    )
    renderer:release()
    world:release()
    resources:release()
    require('validation.tests.integration.shadowCacheRuntime')(test)
end
