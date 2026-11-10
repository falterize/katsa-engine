-- Draws one Beam3D / Trail3D as a single stream mesh through the particle sprite shader, so shader
-- layers, fog-free world lighting and shadow reception behave exactly like particles.
local Geometry = require('./geometry')
local Image = require('../components.media.image')
local Resolver = require('../graphics.shaders.materialResolver')

local R = {}

local format = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexColor', 'float', 4 },
}

local STRETCH_ONLY = { Tiles = true, Texture = true, Atlas = true, XML = true }

-- Texture mapping shared by the visible mesh and the shadow geometry. Returns the Image region
-- (u0, v0, uw, vh) and fills `options` with the along-the-ribbon u mapping.
function R.mapping(node, image, time, options)
    local mode = node.imageMode
    if node.atlasEnabled and mode == 'Decal' then
        mode = 'Atlas'
    end
    local fake = node._clock or {}
    node._clock = fake
    fake.age = math.max(0, time - (node._born or 0))
    local length = math.max(1e-4, node._length or 1)
    local width = math.max(1e-4, node.ribbonKind == 'Beam3D' and math.max(node.width0, node.width1) or node.width)
    options.u0, options.v0, options.uw, options.vh =
        require('source.engine.particles.image').uv(node, fake, image, length, width)
    local textureMode = STRETCH_ONLY[mode] and 'Stretch' or node.textureMode
    local textureLength = math.max(1e-4, node.textureLength)
    local scroll = node.textureSpeed * fake.age
    if textureMode == 'Stretch' then
        options.uOffset, options.uScale = -scroll, 1 / length
        options.static = false
    elseif textureMode == 'Wrap' then
        options.uOffset, options.uScale = -scroll, 1 / textureLength
        options.static = false
    else
        options.uOffset, options.uScale = 0, 1 / textureLength
        options.static = true
        options.staticOffset = -scroll
    end
    return textureMode
end

-- Applies the per-point u of the Static texture mode (world anchored texture).
function R.applyStatic(points, n, options)
    local scale, offset = options.uScale, options.staticOffset or 0
    for i = 1, n do
        local point = points[i]
        point.u = options.static and (point.staticU * scale + offset) or nil
    end
end

function R.options(node, camera, options)
    options = options or {}
    options.faceCamera = node.faceCamera
    options.camera = camera.worldPosition or camera.position
    options.normal = node._normal or { 0, 1, 0 }
    return options
end

function R.draw(system, camera, node)
    local n = node._count or 0
    if n < 2 then
        return
    end
    local world = system.world
    local g = katsa.graphics
    local start = katsa.timer.getTime()
    local time = world.simulationTime or 0
    if not system.shader then
        system.shader = world.resources:own(
            g.newShader(
                require('source.engine.graphics.shaders.shaderSource').read(
                    'assets/shaders/particles/sprite.glsl'
                )
            )
        )
    end
    local image = Image.resolve(world.resources, node, node.texture, world.environment)
    local options = R.options(node, camera, node._stripOptions)
    node._stripOptions = options
    R.mapping(node, image, time, options)
    R.applyStatic(node._points, n, options)
    local vertices = node._vertices or {}
    node._vertices = vertices
    local count = Geometry.strip(node._points, n, options, vertices)
    if count == 0 then
        return
    end
    local capacity = node._meshCapacity or 0
    if capacity < count then
        if node._mesh then
            node._mesh:release()
        end
        capacity = math.max(96, capacity)
        while capacity < count do
            capacity = capacity * 2
        end
        node._mesh = g.newMesh(format, capacity, 'triangles', 'stream')
        node._meshCapacity = capacity
    end
    node._mesh:setTexture(image)
    node._mesh:setVertices(vertices, 1, count)
    node._mesh:setDrawRange(1, count)

    g.push('all')
    local material = Resolver.resolve(world, node)
    local shader = material and material.shader or system.shader
    g.setShader(shader)
    require('source.engine.particles.3d.lighting').bind(shader, world, camera, node)
    shader:send('viewProjection', 'row', camera.viewProjection)
    if material then
        material:bind(world.simulationTime or 0)
    end
    if shader:hasUniform('ribbonPremultiply') then
        shader:send('ribbonPremultiply', true)
        shader:send('ribbonEmission', node.lightEmission)
    end
    if shader:hasUniform('multiplyMode') then
        shader:send('multiplyMode', false)
    end
    g.setDepthMode('less', false)
    g.setMeshCullMode('none')
    g.setColor(1, 1, 1, 1)
    g.setBlendMode('alpha', 'premultiplied')
    g.draw(node._mesh)
    g.pop()
    local stats = system.stats
    stats.drawCalls = stats.drawCalls + 1
    stats.rendered = stats.rendered + math.floor(count / 3)
    stats.drawMilliseconds = stats.drawMilliseconds + (katsa.timer.getTime() - start) * 1000
end

return R
