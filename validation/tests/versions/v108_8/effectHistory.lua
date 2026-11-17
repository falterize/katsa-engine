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
    local settings = require('game.data.settings').create()
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
end

return Module
