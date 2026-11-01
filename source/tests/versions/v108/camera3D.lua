local World = require('source.engine.world.world')
local Picking = require('source.engine.world.picking')
local M = require('source.engine.math.math3d')

local Tests = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-6)
end

local function newCamera(tester, properties)
    local resources = tester.manager.resources:scope()
    local world = World.new(resources)
    properties.position = properties.position or { 0, 0, 0 }
    properties.rotation = properties.rotation or { 0, 0, 0 }
    local camera = world:create('Camera3D', properties)
    camera:update(1280, 720)
    return world, camera, function()
        world:release()
        resources:release()
    end
end

-- Screen position reconstructed from the GPU matrix, as the vertex shader would produce it.
local function matrixScreen(camera, x, y, z)
    local m = camera.viewProjection
    local cx = m[1] * x + m[2] * y + m[3] * z + m[4]
    local cy = m[5] * x + m[6] * y + m[7] * z + m[8]
    local cz = m[9] * x + m[10] * y + m[11] * z + m[12]
    local cw = m[13] * x + m[14] * y + m[15] * z + m[16]
    return camera.width / 2 * (1 + cx / cw), camera.height / 2 * (1 + cy / cw), cz / cw
end

function Tests.lens(tester)
    local _, camera, release = newCamera(tester, { fov = 60 })
    tester:check(
        near(camera.focalLength, 720 / (2 * math.tan(math.rad(30)))),
        'Camera3D fov authors the equivalent focalLength'
    )
    camera.focalLength = 400
    camera:update(1280, 720)
    tester:check(
        near(camera.fov, math.deg(2 * math.atan(720 / 800)), 1e-9),
        'Assigning focalLength updates fov for legacy scenes'
    )
    camera.fov = 90
    camera:update(1280, 720)
    tester:check(near(camera.focalLength, 360, 1e-9), 'Assigning fov wins when it changes last')
    release()
    local _, legacy, releaseLegacy = newCamera(tester, {})
    tester:check(
        legacy.projectionMode == 'Perspective' and near(legacy.focalLength, 400),
        'Cameras without new settings keep the original perspective lens'
    )
    releaseLegacy()
end

function Tests.projection(tester)
    for _, mode in ipairs({ 'Perspective', 'Orthographic' }) do
        local _, camera, release = newCamera(tester, {
            projectionMode = mode,
            orthoSize = 5,
            fov = 70,
            position = { 1, 2, -3 },
            rotation = { 10, 20, 0 },
            near = 0.5,
            far = 200,
        })
        local worst, checked = 0, 0
        for _, p in ipairs({ { 0, 0, 10 }, { 3, -2, 25 }, { -4, 1, 60 }, { 2, 2, 5 } }) do
            local sx, sy = camera:project(p)
            local mx, my = matrixScreen(camera, p[1], p[2], p[3])
            if sx then
                checked = checked + 1
                worst = math.max(worst, math.abs(sx - mx), math.abs(sy - my))
            end
        end
        tester:check(
            checked == 4 and worst < 1e-6,
            mode .. ': project() matches the GPU view-projection matrix'
        )
        release()
    end
    local _, ortho, release = newCamera(tester, { projectionMode = 'Orthographic', orthoSize = 5 })
    local ax, ay = ortho:project({ 2, 1, 10 })
    local bx, by = ortho:project({ 2, 1, 100 })
    tester:check(
        near(ax, bx) and near(ay, by),
        'Orthographic screen position does not change with depth'
    )
    tester:check(
        near(ax - 640, 2 * 720 / 10) and near(360 - ay, 1 * 720 / 10),
        'Orthographic scale is height / (2 * orthoSize) pixels per unit'
    )
    local _, _, nearDepth = matrixScreen(ortho, 0, 0, ortho.near)
    local _, _, farDepth = matrixScreen(ortho, 0, 0, ortho.far)
    tester:check(
        near(nearDepth, -1, 1e-6) and near(farDepth, 1, 1e-6),
        'Orthographic depth maps near to -1 and far to +1'
    )
    release()
end

function Tests.rays(tester)
    local _, ortho, releaseOrtho = newCamera(tester, {
        projectionMode = 'Orthographic',
        orthoSize = 5,
        rotation = { 0, 30, 0 },
        position = { 4, 1, 2 },
    })
    local o1, d1 = ortho:screenRay(100, 100)
    local o2, d2 = ortho:screenRay(900, 500)
    local f = ortho.forward
    tester:check(
        near(d1[1], f[1]) and near(d1[2], f[2]) and near(d1[3], f[3]) and near(d2[1], f[1]),
        'Orthographic pointer rays are parallel to the view direction'
    )
    local gap = math.sqrt((o2[1] - o1[1]) ^ 2 + (o2[2] - o1[2]) ^ 2 + (o2[3] - o1[3]) ^ 2)
    tester:check(
        near(gap, math.sqrt(800 ^ 2 + 400 ^ 2) / ortho.pixelsPerUnit, 1e-6),
        'Orthographic ray origins are spaced by the pixel scale'
    )
    local c1, c2 = ortho:screenRay(640, 360)
    tester:check(
        near(c1[1], 4) and near(c1[2], 1) and near(c1[3], 2) and near(c2[1], f[1]),
        'The orthographic center ray starts at the camera position'
    )
    releaseOrtho()
    local _, persp, releasePersp = newCamera(tester, { fov = 60, position = { 4, 1, 2 } })
    local po1, pd1 = persp:screenRay(100, 100)
    local _, pd2 = persp:screenRay(900, 500)
    tester:check(
        near(po1[1], 4) and not near(pd1[1], pd2[1]),
        'Perspective rays still start at the eye and diverge'
    )
    releasePersp()
end

function Tests.culling(tester)
    local _, camera, release = newCamera(tester, {
        projectionMode = 'Orthographic',
        orthoSize = 5,
        far = 500,
        drawDistance = 1000,
    })
    -- Half-width is 5 * 1280 / 720 = 8.89 units at every depth.
    tester:check(
        camera:visible({ 8, 0, 400 }, 0.1),
        'Orthographic frustum keeps edge objects at depth'
    )
    tester:check(
        not camera:visible({ 12, 0, 400 }, 0.1),
        'Orthographic frustum rejects objects outside the constant side planes'
    )
    tester:check(
        not camera:visible({ 0, 6, 10 }, 0.1) and camera:visible({ 0, 4.9, 10 }, 0.1),
        'Orthographic vertical extent equals orthoSize'
    )
    release()
end

function Tests.picking(tester)
    local world, camera, release = newCamera(tester, {
        projectionMode = 'Orthographic',
        orthoSize = 5,
        position = { 0, 0, -10 },
    })
    local left = world:create('Mesh3D', {
        name = 'LeftCube',
        geometry = world.geometry.cube,
        position = { -3, 0, 20 },
        size = { 2, 2, 2 },
    })
    local right = world:create('Mesh3D', {
        name = 'RightCube',
        geometry = world.geometry.cube,
        position = { 3, 0, 5 },
        size = { 2, 2, 2 },
    })
    camera:update(1280, 720)
    local ppu = camera.pixelsPerUnit
    local hitLeft = Picking.raycast(world, camera, 640 - 3 * ppu, 360)
    local hitRight = Picking.raycast(world, camera, 640 + 3 * ppu, 360)
    local miss = Picking.raycast(world, camera, 640, 360)
    tester:check(
        hitLeft == left and hitRight == right and miss == nil,
        'Orthographic picking hits objects by their constant screen position at any depth'
    )
    release()
end

function Tests.run(tester)
    Tests.lens(tester)
    Tests.projection(tester)
    Tests.rays(tester)
    Tests.culling(tester)
    Tests.picking(tester)
end

return Tests
