-- #shader-<group> tags: a tagged Shader3D/Shader2D acts only on the nodes that carry its tag.
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')
local Resolver = require('source.engine.graphics.shaders.materialResolver')
local UI = require('source.engine.ui')

local Module = {}

local fixtures = 'validation/tests/fixtures/shaders/'

local function active(world, object)
    Resolver.resolve(world, object)
    local names = {}
    for i, shader in ipairs(object._activeShaders or {}) do
        names[i] = shader.name
    end
    return table.concat(names, ',')
end

local function world3D()
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.gizmos.enabled, settings.shadows.enabled = false, false
    return World3D.new(resources, settings), resources
end

local function shader3D(world, name, tag, layer, parent)
    local node = world:create('Shader3D', {
        name = name,
        shaderPath = fixtures .. 'green.glsl',
        shaderLayer = layer,
    }, parent)
    if tag then
        node:addTag(tag)
    end
    return node
end

local function threeD(self)
    local world = world3D()
    local a = world:create('Mesh3D', { name = 'A' })
    local b = world:create('Mesh3D', { name = 'B' })
    local group = world:create('Folder', { name = 'Group' })
    local c = world:create('Mesh3D', { name = 'C' }, group)
    local fx = shader3D(world, 'Fx', '#shader-fx')
    a:addTag('#shader-fx')
    self:check(
        active(world, a) == 'Fx' and active(world, b) == '' and active(world, c) == '',
        'A tagged Shader3D acts only on nodes that carry its tag'
    )
    shader3D(world, 'Local', nil, nil, group)
    c:addTag('#shader-fx')
    self:check(
        active(world, c) == 'Fx,Local' or active(world, c) == 'Local,Fx',
        'An untagged Shader3D keeps its subtree scope next to tagged ones'
    )
    self:check(active(world, b) == '', 'A tag elsewhere never leaks to untagged nodes')
    local before = world._renderInvalidationRevision or 0
    a:removeTag('#shader-fx')
    self:check(
        active(world, a) == '' and (world._renderInvalidationRevision or 0) > before,
        'Removing the tag unbinds the shader and asks the render to resolve again'
    )
    a:addTag('#shader-fx')
    world.shaderLayers:add('Top', 10)
    world.shaderLayers:setInteracts('Top', 'Default3D', false)
    shader3D(world, 'Top', '#shader-fx', 'Top')
    self:check(
        active(world, a) == 'Top',
        'Shader layers apply to tagged shaders: a layer that does not interact suppresses a lower one'
    )
    world.shaderLayers:setInteracts('Top', 'Default3D', true)
    self:check(
        active(world, a) == 'Fx,Top',
        'Tagged shaders sharing a tag stack by layer priority once the layers interact'
    )
    fx:removeTag('#shader-fx')
    self:check(
        active(world, b) == 'Fx',
        'A shader without a #shader- tag goes back to its subtree scope (here the whole world)'
    )
end

local function pixel(data, x, y)
    local r, g, b = data:getPixel(x, y)
    return r, g, b
end

local function twoD(self)
    local world, resources = world3D()
    local width, height = 120, 60
    local ui = UI.new(width, height, resources):bindWorld(world)
    ui.parent = world._node
    ui.layoutMode = 'Fit'
    local red = { 1, 0, 0, 1 }
    local target = ui:container({
        position = { 0, 0, 0, 0 },
        size = { 0, 40, 0, 40 },
        backgroundColor = red,
    }, ui.content)
    local other = ui:container({
        position = { 0, 60, 0, 0 },
        size = { 0, 40, 0, 40 },
        backgroundColor = red,
    }, ui.content)
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
    target:addTag('#shader-fx')
    shot() -- the first frame creates the canvases
    local data = shot()
    local tr, tg, tb = pixel(data, 20, 20)
    local or_, og, ob = pixel(data, 80, 20)
    self:check(
        tr < 0.2 and tg > 0.8 and tb > 0.8 and or_ > 0.8 and og < 0.2 and ob < 0.2,
        'A tagged Shader2D filters the rectangle of the tagged UI node only'
    )
    target:removeTag('#shader-fx')
    shot()
    data = shot()
    tr, tg, tb = pixel(data, 20, 20)
    self:check(tr > 0.8 and tg < 0.2, 'Removing the tag from the target removes the effect')
    target:addTag('#shader-fx')
    world.shaderLayers:add('Top2D', 10)
    world.shaderLayers:setInteracts('Top2D', 'Default2D', false)
    local top = ui:create('Shader2D', {
        name = 'TopInvert',
        shaderPath = fixtures .. 'invert.glsl',
        shaderLayer = 'Top2D',
        size = { 1, 0, 1, 0 },
    }, ui.content)
    top:addTag('#shader-fx')
    shot()
    data = shot()
    tr, tg, tb = pixel(data, 20, 20)
    self:check(
        tr < 0.2 and tg > 0.8 and tb > 0.8,
        'Shader layers apply to tagged Shader2D: a non-interacting upper layer suppresses the lower'
    )
    world.shaderLayers:setInteracts('Top2D', 'Default2D', true)
    shot()
    data = shot()
    tr, tg, tb = pixel(data, 20, 20)
    self:check(
        tr > 0.8 and tg < 0.2 and tb < 0.2,
        'Interacting layers stack on the same target (two inversions give the original)'
    )
    ui:release()
    world:release()
end

local function inspector(self)
    local world = world3D()
    local Properties = require('source.engine.editor.inspectors.properties')
    local function rowOf(node, key)
        for _, row in ipairs(Properties.list(node)) do
            if row.key == key then
                return row
            end
        end
    end
    local mesh = world:create('Mesh3D', { name = 'Tagged' })
    local row = rowOf(mesh, 'tags')
    self:check(row ~= nil, 'The inspector lists the tags in one row')
    self:check(
        Properties.set(nil, mesh, row, 'enemy, #shader-fx') and mesh:hasTag('#shader-fx') and mesh:hasTag('enemy'),
        'Free and engine tags are edited together'
    )
    self:check(
        not Properties.set(nil, mesh, row, '#shader_fx') and mesh:hasTag('enemy'),
        'A malformed engine tag is rejected and nothing changes'
    )
    Properties.set(nil, mesh, row, 'boss')
    self:check(
        mesh:hasTag('boss') and not mesh:hasTag('enemy') and not mesh:hasTag('#shader-fx'),
        'Tags missing from the row are removed'
    )
    world:release()
end

function Module.run(self)
    threeD(self)
    twoD(self)
    inspector(self)
end

return Module
