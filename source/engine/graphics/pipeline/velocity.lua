local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local Affine = require('../../math.affine')
local M = require('../../math.math3d')
local Targets = require('../post.targets')
local Fullscreen = require('../post.fullscreen')
local Programs = require('../shaders.programs')
local SceneTextures = require('./sceneTextures')
local Skinning = require('../../animation.skeleton.skinning')

-- Per-pixel motion of the 3D render: `velocity.rg` = current uv minus the uv the same surface point
-- had last frame, so `history(uv - velocity)` fetches where a pixel came from; `velocity.b` is 1
-- where a moving mesh wrote the value and 0 where only the camera moved. Made on first use in a
-- frame by `Velocity.get`, so a scene without a shader that asks for it pays nothing, except for
-- remembering the last two camera matrices (32 numbers a frame).
--
--   camera motion   a fullscreen pass rebuilds each surface point from the scene depth and projects
--                   it with last frame's camera (sky pixels move with the camera rotation only)
--   mesh motion     meshes whose matrix or bone palette changed are drawn over it, depth-tested
--                   against the scene depth, with their previous matrix and palette
-- Not covered: vertices a user shader displaces, blend shapes, particles, transparent meshes.
local Velocity = {}

-- Remembers the camera matrices. Called once per Renderer:draw; `reused` is true when the frame
-- cache replays the last frame, where nothing moved.
function Velocity.track(renderer, camera, reused)
    local current = renderer._viewProjection
    if not current then
        current, renderer._viewProjection, renderer._previousViewProjection = {}, {}, {}
        current = renderer._viewProjection
        for i = 1, 16 do
            current[i] = camera.viewProjection[i]
        end
    end
    local previous = renderer._previousViewProjection
    for i = 1, 16 do
        previous[i] = current[i]
        if not reused then
            current[i] = camera.viewProjection[i]
        end
    end
end

local function canvasFor(renderer)
    local pool = renderer._velocityTargets
    if not pool then
        pool = Targets.new()
        renderer._velocityTargets = pool
    end
    return Targets.get(pool, renderer, 'velocity', 1, 'rgba16f')
end

local function clearTo(canvas, r, g2, b)
    local g = katsa.graphics
    g.push('all')
    g.setCanvas(canvas)
    g.setScissor()
    g.setStencilTest()
    g.clear(r, g2, b, 1)
    g.pop()
end

local function differs(a, b)
    for i = 1, 16 do
        if a[i] ~= b[i] then
            return true
        end
    end
    return false
end

local function copy(source)
    local result = {}
    for i = 1, 16 do
        result[i] = source[i]
    end
    return result
end

-- What this frame draws of `object`, remembered for the next one: its matrix and bone palette.
local function snapshot(object)
    local matrix = object.combined or object.matrix
    local entry = { matrix = copy(matrix) }
    local skin = object.skin
    if skin then
        entry.palette = {}
        for index, bone in ipairs(skin.matrices) do
            entry.palette[index] = copy(bone)
        end
    end
    return entry
end

local function moved(object, entry)
    if differs(entry.matrix, object.combined or object.matrix) then
        return true
    end
    local skin = object.skin
    if skin and entry.palette then
        for index, bone in ipairs(skin.matrices) do
            if not entry.palette[index] or differs(entry.palette[index], bone) then
                return true
            end
        end
    end
    return false
end

-- Moved opaque meshes with their previous state; updates the memory to this frame.
local function movers(renderer)
    local memory = renderer._velocityMemory
    if not memory or memory.frame ~= renderer.frame - 1 then
        memory = { frame = renderer.frame, objects = setmetatable({}, { __mode = 'k' }) }
        renderer._velocityMemory = memory
    end
    memory.frame = renderer.frame
    local list = {}
    for _, object in ipairs(renderer.opaque) do
        local before = memory.objects[object]
        if not before then
            memory.objects[object] = snapshot(object)
        elseif moved(object, before) then
            list[#list + 1] = { object = object, before = before }
            memory.objects[object] = snapshot(object)
        end
    end
    return list
end

local function cameraPass(renderer, depth, canvas)
    local post = renderer._velocityPost or { shaders = {} }
    renderer._velocityPost = post
    local camera = renderer.camera
    local shader = Fullscreen.shader(post, renderer, 'velocityCamera')
    local reprojection = M.multiply(
        renderer._previousViewProjection,
        Affine.inverse(camera.view, {}),
        {}
    )
    Fullscreen.send(shader, 'reprojection', 'row', reprojection)
    Fullscreen.send(shader, 'projectionScale', { camera.projection[1], camera.projection[6] })
    Fullscreen.send(shader, 'depthRange', { camera.projection[11], camera.projection[12] })
    Fullscreen.send(shader, 'orthographic', camera.orthographic == true)
    Fullscreen.send(shader, 'depthTexture', depth)
    Fullscreen.send(shader, 'depthSize', { depth:getPixelWidth(), depth:getPixelHeight() })
    Fullscreen.draw(renderer.canvas, shader, canvas)
end

local function meshShader(renderer)
    local shader = renderer._velocityShader
    if not shader then
        shader = renderer.resources:own(
            (Programs.compile('assets/shaders/engine/velocity.glsl'))
        )
        renderer._velocityShader = shader
    end
    return shader
end

local function meshPass(renderer, depth, canvas, list)
    if #list == 0 then
        return
    end
    local g = katsa.graphics
    local shader = meshShader(renderer)
    g.push('all')
    g.origin()
    g.setScissor()
    g.setStencilTest()
    g.setCanvas({ canvas, depthstencil = depth })
    g.setFrontFaceWinding('cw')
    g.setShader(shader)
    g.setBlendMode('replace')
    g.setDepthMode('lequal', false)
    g.setWireframe(false)
    shader:send('viewProjection', 'row', renderer.camera.viewProjection)
    shader:send('previousViewProjection', 'row', renderer._previousViewProjection)
    shader:send('instanced', false)
    for _, item in ipairs(list) do
        local object, before = item.object, item.before
        Skinning.bind(shader, object)
        if object.skin and before.palette and #before.palette > 0 then
            shader:send('previousBones', 'row', unpack(before.palette))
        end
        shader:send('model', 'row', object.combined or object.matrix)
        shader:send('previousModel', 'row', before.matrix)
        g.setMeshCullMode(object.doubleSided and 'none' or 'back')
        g.draw(object.geometry.mesh)
    end
    g.pop()
end

-- A 1x1 velocity of zero (no 3D render under the effect), kept on `owner` (a UI).
function Velocity.zero(owner)
    if not owner._zeroVelocity then
        local data = katsa.image.newImageData(1, 1, 'rgba16f')
        data:setPixel(0, 0, 0, 0, 0, 1)
        owner._zeroVelocity = owner.resources:own(katsa.graphics.newImage(data))
    end
    return owner._zeroVelocity
end

-- The velocity canvas of the frame the renderer drew last (zero while the frame cache replays it).
function Velocity.get(renderer)
    local canvas = canvasFor(renderer)
    if renderer.stats.frameReused then
        if renderer._velocityShown ~= 'zero' then
            clearTo(canvas, 0, 0, 0)
            renderer._velocityShown = 'zero'
        end
        return canvas
    end
    if renderer._velocityShown == renderer.frame then
        return canvas
    end
    renderer._velocityShown = renderer.frame
    local depth = SceneTextures.depth(renderer)
    local g = katsa.graphics
    g.push('all')
    cameraPass(renderer, depth, canvas)
    meshPass(renderer, depth, canvas, movers(renderer))
    g.pop()
    return canvas
end

function Velocity.release(renderer)
    if renderer._velocityTargets then
        Targets.release(renderer._velocityTargets)
        renderer._velocityTargets = nil
    end
    if renderer._velocityPost then
        renderer._velocityPost = nil
    end
    renderer._velocityShown, renderer._velocityMemory = nil, nil
end

return Velocity
