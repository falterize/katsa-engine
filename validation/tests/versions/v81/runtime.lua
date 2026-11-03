local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED v81 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:update() end

function T:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v81 ' .. label)
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    local Opacity = require('source.engine.materials.opacity')
    local scene = self.manager:switch(require('source.game.runtime.game').new, 'occlusion')
    local world, renderer, camera = scene.world, scene.renderer, scene.camera
    world.environment.render.frameCache = false
    world.environment.shadows.enabled = false
    world.environment.sky.enabled = false
    self:check(
        Opacity.image(scene.resources:image('bricks')),
        'Inherited brick texture classified opaque at load'
    )
    local pixels = katsa.image.newImageData(4, 4)
    pixels:mapPixel(function()
        return 1, 1, 1, 1
    end)
    local solid = scene.resources:loadImage(pixels, 'solid-test')
    pixels:setPixel(1, 1, 1, 1, 1, 0)
    local holes = scene.resources:loadImage(pixels, 'hole-test')
    self:check(
        Opacity.image(solid) and not Opacity.image(holes),
        'One transparent texel prevents solid coverage'
    )
    pixels:release()
    local Coverage = require('source.engine.graphics.occlusion.coverage')

    local function polygon(x1, x2)
        local p =
            { { x1, 0, 5 }, { x2, 0, 5 }, { x2, 100, 5 }, { x1, 100, 5 }, sign = 1, depth = 5 }
        Coverage.describe(p)
        return p
    end
    local points = { 20, 20, 80, 20, 80, 80, 20, 80 }
    local a, b = polygon(0, 60), polygon(40, 100)
    self:check(
        not Coverage.single(points, 10, a) and not Coverage.single(points, 10, b),
        'Neither occluder covers the target alone'
    )
    self:check(
        Coverage.test(points, 10, { a, b }, nil, { unionBudget = 4096 }),
        'Two overlapping occluders cover the target together'
    )
    self:check(
        Coverage.test(points, 10, { polygon(0, 50), polygon(50, 100) }, nil, { unionBudget = 4096 }),
        'Shared occluder seam remains closed'
    )
    self:check(
        not Coverage.test(
            points,
            10,
            { polygon(0, 49), polygon(51, 100) },
            nil,
            { unionBudget = 4096 }
        ),
        'Real gap between occluders remains visible'
    )
    self:check(
        not Coverage.test(points, 4, { a, b }, nil, { unionBudget = 4096 }),
        'Union cannot hide a target in front'
    )
    self:check(
        not Coverage.test(points, 10, { a, b }, nil, { unionBudget = 0 }),
        'Exhausted coverage budget retains geometry'
    )

    local function capture(occlusion, prepass)
        world.environment.render.occlusionCulling = occlusion
        world.environment.render.depthPrepass = prepass
        renderer:draw(world, camera, 1, true)
        local image = renderer.canvas:newImageData()
        local bytes = image:getString()
        image:release()
        return bytes
    end
    scene.demo.wall.visible = false
    local most = 0
    for i = 1, 3 do
        camera.position, camera.rotation = { -6 + (i - 1) * 12, 5, -10 }, { 0, (i - 1) * 8, 0 }
        local off = capture(false, false)
        local on = capture(true, false)
        self:check(off == on, 'Inherited cube rows exact image at pose ' .. i)
        most = math.max(most, renderer.stats.occlusionCulled)
        print(
            'ROW_SAVINGS',
            renderer.stats.meshTrianglesBeforeOcclusion,
            renderer.stats.meshTrianglesAfterOcclusion,
            renderer.stats.occlusionCulled
        )
    end
    self:check(most > 0, 'Inherited cubes now hide cubes behind them')
    for _, object in ipairs({ unpack(world.objects) }) do
        object:destroy()
    end
    local Geometry = require('source.engine.graphics.geometry.primitives')
    local quad = Geometry.quad()
    scene.resources:own(quad.mesh)
    local plane = world:create('Mesh3D', {
        name = 'FacingPlane',
        geometry = quad,
        position = { 0, 0, 10 },
        size = { 40, 40, 1 },
        lightInfluence = 0,
        color = { 0.2, 0.8, 0.9 },
        doubleSided = false,
    })
    local facingTarget = world:create(
        'Mesh3D',
        { name = 'FacingTarget', position = { 0, 0, 25 }, size = { 4, 4, 4 }, lightInfluence = 0 }
    )
    camera.position, camera.rotation = { 0, 0, 0 }, { 0, 0, 0 }
    for _, angle in ipairs({ 0, 180 }) do
        plane.rotation[2] = angle
        self:check(
            capture(false, false) == capture(true, false),
            'Single-sided panel exact image at angle ' .. angle
        )
    end
    plane.doubleSided = true
    plane.rotation[2] = 0
    facingTarget.transparency = 0.25
    capture(true, false)
    facingTarget.position[1] = 20
    self:check(
        capture(false, false) == capture(true, false),
        'Moving target invalidates only its own cached visibility'
    )
    self:check(
        renderer.stats.occlusionGeometryReused,
        'Static occluder geometry survives independent target motion'
    )
    local Masks = require('source.engine.graphics.occlusion.indexMasks')
    local state = {}
    Masks.begin(state)
    local first, second = { geometry = { mesh = quad.mesh } }, { geometry = { mesh = quad.mesh } }
    self:check(
        Masks.select(state, first, { 1, 2, 3 }) == Masks.select(state, second, { 1, 2, 3 }),
        'Identical masks share a draw mesh'
    )
    Masks.release(state)
    scene = self.manager:switch(require('source.game.runtime.game').new, 'combined')
    world, renderer, camera = scene.world, scene.renderer, scene.camera
    world.environment.render.frameCache = false
    world.environment.shadows.sourceFadeSeconds = 0
    world.environment.shadows.maxUpdateFaces = 195
    world.environment.gizmos.enabled = false
    world.environment.shadows.enabled = false
    for i = 1, 3 do
        camera.position[1] = camera.position[1] + 8
        world.byName['Cube10.2'].rotation[2] = i * 20
        local off = capture(false, false)
        local on = capture(false, true)
        self:check(off == on, 'Depth prepass exact image under camera/object motion ' .. i)
        self:check(renderer.depthPrepassActive, 'Dense opaque lit scene uses early depth')
    end
    world.environment.shadows.enabled = true
    renderer.shadows.nextUpdate = 0
    local off = capture(false, false)
    renderer.shadows.nextUpdate = 0
    self:check(off == capture(false, true), 'Depth prepass preserves Sun/Point/Spot shadows')
    world.environment.shadows.enabled = false
    world.environment.render.renderDensity = 2
    self:check(
        capture(false, false) == capture(false, true),
        'Depth prepass exact image at density 2'
    )
    world.environment.render.renderDensity = 1
    world.environment.render.msaa = 2
    capture(false, true)
    if renderer.actualMSAA > 0 then
        self:check(not renderer.depthPrepassActive, 'MSAA retains the original render path')
    else
        print('SKIP actual multisample canvas unavailable on this driver')
    end
    world.environment.render.msaa = 0
    local object = world.byName['Cube10.2']
    for _, child in ipairs({ unpack(object.children) }) do
        if child:isA('SurfaceAppearance3D') then
            child:destroy()
        end
    end
    local cutout = katsa.image.newImageData(4, 4)
    cutout:mapPixel(function()
        return 1, 1, 1, 1
    end)
    cutout:setPixel(1, 1, 1, 1, 1, 0)
    local cutoutImage = scene.resources:loadImage(cutout, 'cutout-test')
    cutout:release()
    world:create('SurfaceAppearance3D', { colorMap = cutoutImage, alphaMode = 'Inherit' }, object)
    self:check(
        capture(false, false) == capture(false, true) and not renderer.depthPrepassActive,
        'Unknown/cutout alpha retains the original render path'
    )
    local custom = require('source.engine.graphics.material').new(
        scene.resources,
        { fragmentCode = 'result*=vec3(1.0);' }
    )
    self:check(
        not custom.shader:hasUniform('depthPrepassTexture'),
        'Custom materials retain their original sampler interface'
    )
    local valid, errors = katsa.graphics.validateShader(
        true,
        require('source.engine.graphics.shaderSource').read(
            'assets/shaders/engine/depthPrepass.glsl'
        )
    )
    self:check(valid, 'Depth shader validates for ES: ' .. tostring(errors))
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' focused v81 checks')
    katsa.event.quit()
end

return T
