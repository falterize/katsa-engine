-- Shader follow-ups: linear_depth, sampler textures (path / node), sampler hints, 2D screen texture.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Renderer = require('source.engine.graphics.pipeline.renderer')
local UniformEditor = require('source.engine.editor.inspectors.uniformEditor')
local UI = require('source.engine.ui')

local Module = {}

local WIDTH, HEIGHT = 120, 60
local fixtures = 'validation/tests/fixtures/shaders/'

local function newWorld()
    local resources = Resources.new(require('validation.tests.fixtures.manifest'))
    local settings = require('game.data.settings').create()
    settings.gizmos.enabled, settings.shadows.enabled = false, false
    local world = World3D.new(resources, settings)
    local camera = world:addCamera({ position = { 0, 5, 0 }, rotation = { 0, 0, 0 }, drawDistance = 800 })
    local renderer = Renderer.new(resources)
    renderer.targetWidth, renderer.targetHeight = WIDTH, HEIGHT
    world.environment.render.msaa, world.environment.render.renderDensity = 0, 1
    return world, camera, renderer, resources
end

local function threeD(self)
    local world, camera, renderer = newWorld()
    local clock = 0
    local function shot()
        clock = clock + 1
        return renderer:draw(world, camera, clock, true):newImageData()
    end
    world:create('Mesh3D', { name = 'Wall', position = { 0, 5, 40 }, size = { 200, 100, 2 }, color = { 1, 1, 1, 1 } })
    local pane = world:create('Mesh3D', {
        name = 'Pane',
        position = { 0, 5, 10 },
        size = { 80, 40, 1 },
        color = { 1, 1, 1, 1 },
    })
    local shader = world:create('Shader3D', {
        name = 'Depth',
        shaderPath = fixtures .. 'linearDepth.glsl',
    }, pane)
    local r = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(
        math.abs(r * 100 - 39) < 1.5,
        ('linear_depth turns hint_depth_texture into view distance (%.1f, wall front at 39)'):format(r * 100)
    )

    shader.shaderPath = fixtures .. 'samplerTexture.glsl'
    shader.uniforms.tex = 'white'
    local white = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    shader.uniforms.tex = 'dirt'
    local dirt = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(white > 0.95 and dirt < 0.9, 'A sampler2D uniform takes a texture path or name')

    local ui = UI.new(WIDTH, HEIGHT, world.resources):bindWorld(world)
    local frame = ui:create('ViewportFrame', { name = 'Frame', size = { 0, 40, 0, 40 } }, ui.content)
    self:check(frame.getTexture and frame:getTexture() == nil, 'A ViewportFrame offers its texture once it has drawn')
    shader.uniforms.tex = frame
    local ok = pcall(shot)
    local source = katsa.graphics.newCanvas(4, 4)
    katsa.graphics.setCanvas(source)
    katsa.graphics.clear(1, 0, 0, 1)
    katsa.graphics.setCanvas()
    shader.uniforms.tex = { getTexture = function() return source end }
    local red, green = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(red > 0.9 and green < 0.1, 'A node that offers getTexture() feeds its live texture to the sampler')
    self:check(ok, 'A node without a texture yet leaves the sampler unset instead of failing')
end

local function editor(self)
    local world = newWorld()
    local node = world:create('Shader3D', { name = 'Tex', shaderPath = fixtures .. 'samplerTexture.glsl' })
    local rows = {}
    local popup = { target = node, body = {}, ui = { container = function() end } }
    function popup:input(label, text, _, apply)
        rows[label] = { text = text, apply = apply }
    end
    UniformEditor.open(popup)
    local row = rows['tex (texture path)']
    self:check(row and row.apply('stone') and node.uniforms.tex == 'stone', 'The uniform editor lists sampler2D uniforms as texture paths')
end

local function twoD(self)
    local world, _, _, resources = newWorld()
    local ui = UI.new(WIDTH, HEIGHT, resources):bindWorld(world)
    ui.parent = world._node
    ui.layoutMode = 'Fit'
    ui:container({ position = { 0, 0, 0, 0 }, size = { 1, 0, 1, 0 }, backgroundColor = { 1, 0, 0, 1 } }, ui.content)
    ui:create('Shader2D', {
        name = 'Swap',
        shaderPath = fixtures .. 'screen2D.glsl',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
    }, ui.content)
    local canvas = katsa.graphics.newCanvas(WIDTH, HEIGHT)
    local function shot()
        katsa.graphics.setCanvas(canvas)
        katsa.graphics.clear(0, 0, 0, 1)
        ui:draw()
        katsa.graphics.setCanvas()
        return canvas:newImageData()
    end
    shot()
    local r, _, b = shot():getPixel(WIDTH / 2, HEIGHT / 2)
    self:check(b > 0.8 and r < 0.2, 'hint_screen_texture in a canvas_item shader reads the snapshot being processed')
end

function Module.run(self)
    threeD(self)
    editor(self)
    twoD(self)
end

return Module
