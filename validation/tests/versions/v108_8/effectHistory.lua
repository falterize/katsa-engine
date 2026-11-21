-- hint_history_texture (a Shader2D's own previous result) and hint_velocity_texture (per-pixel
-- motion of the 3D render) in canvas_item shaders.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Renderer = require('source.engine.graphics.pipeline.renderer')
local UI = require('source.engine.ui')

local Module = {}

local WIDTH, HEIGHT = 96, 54
local fixtures = 'validation/tests/fixtures/shaders/'

local function build()
    local resources = Resources.new(require('validation.tests.fixtures.manifest'))
    local settings = require('source.runtime.settings').create()
    settings.gizmos.enabled, settings.shadows.enabled = false, false
    local world = World3D.new(resources, settings)
    local camera = world:addCamera({ position = { 0, 0, 0 }, rotation = { 0, 0, 0 }, drawDistance = 200 })
    world:create('Mesh3D', { name = 'Wall', position = { 0, 0, 20 }, size = { 200, 100, 2 }, color = { 1, 1, 1, 1 } })
    local renderer = Renderer.new(resources)
    renderer.targetWidth, renderer.targetHeight = WIDTH, HEIGHT
    world.environment.render.msaa, world.environment.render.renderDensity = 0, 1
    local ui = UI.new(WIDTH, HEIGHT, resources):bindWorld(world)
    ui.parent = world._node
    ui.layoutMode = 'Fit'
    return world, camera, renderer, ui
end

function Module.run(self)
    local world, camera, renderer, ui = build()
    local panel = ui:container({
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        backgroundColor = { 1, 0, 0, 1 },
    }, ui.content)
    local canvas = katsa.graphics.newCanvas(WIDTH, HEIGHT)
    local frame = 0
    local function shot(withScene)
        frame = frame + 1
        if withScene then
            renderer:draw(world, camera, frame, true)
            ui.backgroundRenderer, ui.backgroundCanvas = renderer, renderer.canvas
        end
        katsa.graphics.setCanvas(canvas)
        katsa.graphics.clear(0, 0, 0, 1)
        ui:draw()
        katsa.graphics.setCanvas()
        return canvas:newImageData()
    end

    shot()
    local effect = ui:create('Shader2D', {
        name = 'Feedback',
        shaderPath = fixtures .. 'history2D.glsl',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
    }, ui.content)
    shot()
    local r, _, b = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(r > 0.95 and b < 0.05, 'A history shader created on a laid-out picture starts from that picture')
    panel.backgroundColor = { 0, 0, 1, 1 }
    r, _, b = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(math.abs(r - 0.5) < 0.05 and math.abs(b - 0.5) < 0.05, 'The next frame blends with the previous result')
    r, _, b = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(math.abs(r - 0.25) < 0.05 and math.abs(b - 0.75) < 0.05, 'The blend feeds back frame after frame')

    effect:destroy()
    panel.visible = false
    world.shaderLayers:setInteracts('Default2D', 'Default3D', true)
    ui:create('Shader2D', {
        name = 'Motion',
        shaderPath = fixtures .. 'velocity2D.glsl',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
    }, ui.content)
    shot(true)
    local still = shot(true):getPixel(WIDTH / 2, HEIGHT / 2)
    camera.position = { 2, 0, 0 }
    local moved = shot(true):getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(math.abs(still - 0.5) < 0.02, 'A still camera gives zero velocity')
    self:check(math.abs(moved - 0.5) > 0.05, 'A moving camera gives a non-zero velocity to the shader')
    ui.backgroundRenderer, ui.backgroundCanvas = nil, nil
    local none = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(math.abs(none - 0.5) < 0.02, 'Without a 3D render the velocity is zero')

    -- The same hint in a spatial shader: a pane in front of the wall shows the motion behind it.
    local world3, camera3, renderer3 = build()
    local pane = world3:create('Mesh3D', {
        name = 'Pane',
        position = { 0, 0, 10 },
        size = { 80, 40, 1 },
        color = { 1, 1, 1, 1 },
    })
    world3:create('Shader3D', { name = 'MotionPane', shaderPath = fixtures .. 'velocity3D.glsl' }, pane)
    local clock = 0
    local function pixel()
        clock = clock + 1
        camera3:update(WIDTH, HEIGHT)
        local data = renderer3:draw(world3, camera3, clock, true):newImageData()
        return (data:getPixel(WIDTH / 2, HEIGHT / 2))
    end
    pixel()
    local steady = pixel()
    camera3.position = { 2, 0, 0 }
    local panned = pixel()
    self:check(math.abs(steady - 0.5) < 0.02, 'A spatial shader reads zero velocity while nothing moves')
    self:check(
        math.abs(panned - 0.5) > 0.05,
        ('A spatial shader reads the camera motion through hint_velocity_texture (%.2f -> %.2f)'):format(steady, panned)
    )
    -- The Datamosh demo shader tears a pinned frame along the motion: after the camera pans for a
    -- few frames the picture differs from the live render of the same pose.
    local world4, camera4, renderer4, ui4 = build()
    for i = 1, 5 do
        world4:create('Mesh3D', {
            name = 'Block' .. i,
            position = { -12 + i * 5, 0, 18 },
            size = { 3, 20, 1 },
            color = { i % 2, 1 - i % 2, 0.3 * i % 1, 1 },
        })
    end
    world4.shaderLayers:setInteracts('Default2D', 'Default3D', true)
    local mosh = ui4:create('Shader2D', {
        name = 'Mosh',
        shaderPath = 'game/scenes/stareShooter/assets/shaders/datamosh.glsl',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        animated = true,
        uniforms = { pin = 0 },
    }, ui4.content)
    local out = katsa.graphics.newCanvas(WIDTH, HEIGHT)
    local tick = 0
    local function mosh4()
        tick = tick + 1
        camera4:update(WIDTH, HEIGHT)
        renderer4:draw(world4, camera4, tick, true)
        ui4.backgroundRenderer, ui4.backgroundCanvas = renderer4, renderer4.canvas
        katsa.graphics.setCanvas(out)
        katsa.graphics.clear(0, 0, 0, 1)
        katsa.graphics.draw(renderer4.canvas)
        ui4:draw()
        katsa.graphics.setCanvas()
        return out:newImageData()
    end
    for _ = 1, 4 do
        mosh4()
    end
    mosh.uniforms = { pin = 1 }
    local x = 0
    for _ = 1, 8 do
        x = x + 0.15
        camera4.position = { x, 0, 0 }
        mosh4()
    end
    local torn = mosh4()
    mosh.enabled = false
    local live = mosh4()
    local changed = 0
    for y = 0, HEIGHT - 1, 2 do
        for px = 0, WIDTH - 1, 2 do
            local r1, g1, b1 = torn:getPixel(px, y)
            local r2, g2, b2 = live:getPixel(px, y)
            if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.15 then
                changed = changed + 1
            end
        end
    end
    self:check(
        changed > 20,
        ('A pinned Datamosh pushes pixels along the camera motion (%d sampled pixels differ from live)'):format(changed)
    )
end

return Module
