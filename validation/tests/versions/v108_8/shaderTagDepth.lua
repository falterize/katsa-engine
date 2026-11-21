-- #shader- / #noshader- tags reach descendants; depth attributes and exclusions bound them.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Resolver = require('source.engine.graphics.shaders.materialResolver')
local UI = require('source.engine.ui')

local Module = {}

local fixtures = 'validation/tests/fixtures/shaders/'

local function world3D()
    local resources = Resources.new(require('validation.tests.fixtures.manifest'))
    local settings = require('source.runtime.settings').create()
    settings.gizmos.enabled, settings.shadows.enabled = false, false
    return World3D.new(resources, settings), resources
end

-- Which of the chain R > A > B > C > D carry the shader, as a string like 'RABC' ('-' when not).
local function reach(world, chain)
    local out = {}
    for i, node in ipairs(chain) do
        Resolver.resolve(world, node)
        out[i] = #(node._activeShaders or {}) > 0 and node.name or '-'
    end
    return table.concat(out)
end

local function chain(world)
    local nodes, parent = {}, nil
    for i, name in ipairs({ 'R', 'A', 'B', 'C', 'D' }) do
        nodes[i] = world:create('Mesh3D', { name = name }, parent)
        parent = nodes[i]
    end
    return nodes
end

local function threeD(self)
    local world = world3D()
    local nodes = chain(world)
    local R, A, B, C = nodes[1], nodes[2], nodes[3], nodes[4]
    local fx = world:create('Shader3D', { name = 'Fx', shaderPath = fixtures .. 'green.glsl' })
    fx:addTag('#shader-fx')
    R:addTag('#shader-fx')
    self:check(reach(world, nodes) == 'RABCD', 'A tag with no depth reaches the whole subtree')
    R:setAttribute('shaderDepth.fx', 1)
    self:check(reach(world, nodes) == 'RA---', 'shaderDepth.<group> limits the levels below the node')
    R:setAttribute('shaderDepth.fx', 0)
    self:check(reach(world, nodes) == 'R----', 'Depth 0 is the tagged node only')
    R:setAttribute('shaderDepth.fx', nil)
    R:setAttribute('shaderDepth.fx', 3)
    self:check(reach(world, nodes) == 'RABC-', 'shaderDepth.<group> 3 reaches three levels below')
    R:setAttribute('shaderDepth.fx', nil)

    B:addTag('#noshader-fx')
    self:check(reach(world, nodes) == 'RA---', '#noshader excludes the node and its subtree')
    B:setAttribute('noShaderDepth.fx', 0)
    self:check(reach(world, nodes) == 'RA-CD', 'noShaderDepth 0 skips only that node')
    B:removeTag('#noshader-fx')
    B:setAttribute('noShaderDepth.fx', nil)

    A:addTag('#noshader-fx')
    C:addTag('#shader-fx')
    self:check(reach(world, nodes) == 'R--CD', 'A tag further down includes again inside an exclusion')
    A:removeTag('#noshader-fx')
    C:removeTag('#shader-fx')

    R:addTag('#noshader-fx')
    self:check(reach(world, nodes) == '-----', 'Exclusion beats inclusion on the same node')
    R:setAttribute('shaderDepth.fx', 3)
    R:setAttribute('noShaderDepth.fx', 1)
    self:check(reach(world, nodes) == '--BC-', 'Include 3 with exclude 1 leaves levels 2 and 3')

    local before = world._renderInvalidationRevision or 0
    R:setAttribute('shaderDepth.fx', 2)
    self:check(
        (world._renderInvalidationRevision or 0) > before,
        'Changing a depth attribute asks the render to resolve again'
    )
    world:release()
end

local function pixel(data, x, y)
    local r, g, b = data:getPixel(x, y)
    return r, g, b
end

local function twoD(self)
    local world, resources = world3D()
    local width, height = 80, 60
    local ui = UI.new(width, height, resources):bindWorld(world)
    ui.parent = world._node
    ui.layoutMode = 'Fit'
    local red, blue = { 1, 0, 0, 1 }, { 0, 0, 1, 1 }
    local outer = ui:container({
        position = { 0, 0, 0, 0 },
        size = { 0, 60, 0, 60 },
        backgroundColor = red,
    }, ui.content)
    local inner = ui:container({
        position = { 0, 20, 0, 20 },
        size = { 0, 20, 0, 20 },
        backgroundColor = blue,
    }, outer)
    local effect = ui:create('Shader2D', {
        name = 'Invert',
        shaderPath = fixtures .. 'invert.glsl',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
    }, ui.content)
    local canvas = katsa.graphics.newCanvas(width, height)
    local function shot()
        katsa.graphics.setCanvas(canvas)
        katsa.graphics.clear(0, 0, 0, 1)
        ui:draw()
        katsa.graphics.setCanvas()
        return canvas:newImageData()
    end
    effect:addTag('#shader-fx')
    outer:addTag('#shader-fx')
    shot()
    local data = shot()
    local r1, g1, b1 = pixel(data, 5, 5)
    local r2, g2, b2 = pixel(data, 30, 30)
    self:check(
        r1 < 0.2 and g1 > 0.8 and b1 > 0.8 and r2 > 0.8 and g2 > 0.8 and b2 < 0.2,
        'A tagged UI node and its children are filtered together (red -> cyan, blue -> yellow)'
    )
    inner:addTag('#noshader-fx')
    shot()
    data = shot()
    r1, g1, b1 = pixel(data, 5, 5)
    r2, g2, b2 = pixel(data, 30, 30)
    self:check(
        r1 < 0.2 and g1 > 0.8 and r2 < 0.2 and g2 < 0.2 and b2 > 0.8,
        '#noshader cuts the child out of the effect and keeps its own colours'
    )
    ui:release()
    world:release()
end

function Module.run(self)
    threeD(self)
    twoD(self)
end

return Module
