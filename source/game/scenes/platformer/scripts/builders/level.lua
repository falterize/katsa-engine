local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')

local L = {}

function L.build(lab)
    local world = lab.scene.world

    local function platform(name, p, size, color)
        local body = world:create('Body3D', {
            name = name,
            bodyType = 'Static',
            position = p,
            collider = { shape = 'Box', size = size },
            friction = 0.6,
        })
        Mesh.create(world, {
            name = name .. 'Visual',
            size = size,
            color = color or { 0.2, 0.35, 0.45 },
            surfaceAppearance = { colorMap = 'stone' },
        }, body)
        return body
    end
    platform('StartIsland', { 0, -6, -30 }, { 260, 12, 210 })
    local points = {
        { 0, 12, 110 },
        { 35, 30, 190 },
        { -30, 48, 275 },
        { 30, 66, 370 },
        { 0, 84, 465 },
        { -45, 90, 555 },
        { 35, 105, 645 },
        { 0, 115, 735 },
    }
    lab.pickups = {}
    for i, p in ipairs(points) do
        platform('Platform' .. i, p, { 65, 12, 65 })
        local group = world:create('Node3D', { name = 'CrystalGroup' .. i })
        local shader = world:create('Shader3D', {
            name = 'CrystalShader' .. i,
            shaderPath = 'assets/shaders/examples/tint3D.glsl',
            uniforms = { tintEffect = { 0.7, 1, 1.4 } },
        }, group)
        local gem = Mesh.create(world, {
            name = 'Crystal' .. i,
            kind = 'sphere',
            position = { p[1], p[2] + 24, p[3] },
            size = { 7, 7, 7 },
            color = { 0.2, 0.8, 1 },
            unlit = true,
        }, shader)
        lab.pickups[i] = { mesh = gem, position = p, collected = false }
    end
    platform('FinishIsland', { 0, 115, 830 }, { 220, 12, 140 }, { 0.25, 0.5, 0.35 })
    platform('DashPractice', { 145, -6, -30 }, { 90, 12, 210 })
    platform('PracticeStep1', { -100, 12, -70 }, { 45, 12, 45 })
    platform('PracticeStep2', { -100, 30, -10 }, { 45, 12, 45 })
    platform('SlideGateRoof', { 0, 28, 25 }, { 45, 6, 28 }, { 0.8, 0.3, 0.1 })
    local mix = Mesh.create(world, {
        name = 'MaterialMixColumn',
        position = { -45, 22, -10 },
        size = { 16, 44, 16 },
        color = {
            1,
            1,
            1,
        },
    })
    lab.materialA =
        world:create('SurfaceAppearance3D', { name = 'StoneSurface', colorMap = 'stone' }, mix)
    lab.materialB = world:create(
        'SurfaceAppearance3D',
        { name = 'BrickSurface', colorMap = 'bricks', transparency = 1 },
        mix
    )
    lab.materialProgress = 0
    lab.spawn = { 0, 20, -35 }
end

return L
