-- Shader2D touches interface pixels only unless its shader layer interacts with Default3D; Shader3D belongs to World3D space.
local Application = require('source.runtime.application')

local Module = {}

local function render(scene, effect)
    local g = katsa.graphics
    local w, h = g.getDimensions()
    local canvas = g.newCanvas(w, h, { dpiscale = 1 })
    g.push('all')
    g.setCanvas({ canvas, stencil = true })
    -- A flat colour stands in for the 3D render underneath the interface.
    g.clear(0.2, 0.4, 0.6, 1)
    scene.root:find('World3D/World2D'):fit(w, h)
    scene.root:find('World3D/World2D'):draw()
    g.pop()
    local data = canvas:newImageData()
    local r, gr, b, a = data:getPixel(2, 2)
    canvas:release()
    data:release()
    return r, gr, b, a
end

function Module.run(self)
    local scene = Application.new(self.manager, 'models')
    scene:load()
    scene:update(1 / 60, 1 / 60)
    local ui = scene.root:find('World3D/World2D')
    local effect = ui:create('Shader2D', {
        _viewportAuthored = true,
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        zIndex = 500,
        backgroundTransparency = 1,
        shaderPath = 'validation/tests/fixtures/shaders/invert.glsl',
    }, ui.content)
    for _, list in ipairs({ ui.children, ui.content.children }) do
        for _, child in ipairs(list) do
            if child ~= effect and child ~= ui.content then
                child.visible = false
            end
        end
    end
    local layers = scene.world.shaderLayers
    self:check(not layers:affects3D(effect.shaderLayer), 'Shader2D ignores the 3D render by default')
    local r, g, b = render(scene, effect)
    self:check(
        math.abs(r - 0.2) < 0.02 and math.abs(g - 0.4) < 0.02 and math.abs(b - 0.6) < 0.02,
        ('Shader2D leaves the 3D render untouched by default (%.2f %.2f %.2f)'):format(r, g, b)
    )
    layers:add('Screen', 10)
    effect.shaderLayer = 'Screen'
    r, g, b = render(scene, effect)
    self:check(
        math.abs(r - 0.8) < 0.02 and math.abs(g - 0.6) < 0.02 and math.abs(b - 0.4) < 0.02,
        ('Shader2D on a layer interacting with Default3D processes the 3D render (%.2f %.2f %.2f)'):format(r, g, b)
    )
    effect.shaderLayer = 'Default2D'
    r, g, b = render(scene, effect)
    self:check(math.abs(r - 0.2) < 0.02, 'Moving back to Default2D leaves the 3D render untouched')

    -- Shader3D is rejected inside interface hierarchies and accepted inside World3D hierarchies.
    local world = scene.world
    local frame = ui:container({ size = { 0, 10, 0, 10 } }, ui.content)
    self:check(
        not pcall(world.create, world, 'Shader3D', { shaderPath = '' }, frame),
        'Shader3D cannot live under a UI node'
    )
    local folder = world:create('Folder', { name = 'ShaderScope' })
    local ok, shader = pcall(world.create, world, 'Shader3D', { shaderPath = '' }, folder)
    self:check(ok and shader.parent == folder, 'Shader3D accepts a Folder inside World3D')
    scene:release()
end

return Module
