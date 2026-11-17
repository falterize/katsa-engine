-- LODGroup effects: quality bias, zoom compensation, animation rates, shadow level, cross-fade and
-- the billboard level.
local Application = require('game.runtime.application')
local Plugins = require('source.engine.plugins')
local Models = require('source.engine.import.models')
local Profiles = require('source.engine.graphics.quality.profiles')
local Renderer = require('source.engine.graphics.pipeline.renderer')
local Resources = require('source.engine.core.resources')
local World3D = require('source.engine.world.world')

local Module = {}

local function levelAt(group, world, camera, z)
    camera.position = { 0, 0, z }
    world.activeCamera:update(1280, 720)
    group:update(0.1)
    return group:getLevel()
end

local function cubes(world, group, names)
    local meshes = {}
    for index, name in ipairs(names) do
        meshes[index] = world:create('Mesh3D', { name = name, size = { 1, 1, 1 } }, group)
    end
    return meshes
end

local function checkBillboard(self)
    local resources = Resources.new(require('validation.tests.fixtures.manifest'))
    local settings = require('game.data.settings').create()
    settings.gizmos.enabled, settings.shadows.enabled = false, false
    local world = World3D.new(resources, settings)
    Plugins.activate(world, { 'lod' })
    local camera = world:addCamera({ position = { 0, 2, -10 }, rotation = { 0, 0, 0 }, drawDistance = 800 })
    world.environment.sky.enabled = false
    local renderer = Renderer.new(resources)
    renderer.targetWidth, renderer.targetHeight = 160, 90
    world.environment.render.msaa, world.environment.render.renderDensity = 0, 1
    local group = world:create('LODGroup', {
        name = 'Far',
        distances = '5',
        radius = 4,
        billboardImage = 'validation/tests/fixtures/lodBillboard.png',
        billboardWidth = 4,
        billboardHeight = 4,
        billboardPivot = 'Center',
    })
    world:create('Mesh3D', { name = 'Near', size = { 1, 1, 1 } }, group)
    group:update(0.1)
    local quad = world.byName.FarBillboard
    camera:update(160, 90)
    local clock = 0
    local function look(x, z, yaw)
        camera.position = { x, 0, z }
        camera.rotation = { 0, yaw, 0 }
        camera:update(160, 90)
        world:updateNodes(0.1)
        clock = clock + 1
        return renderer:draw(world, camera, clock, true):newImageData()
    end
    local front = look(0, -12, 0)
    local r, g = front:getPixel(75, 45)
    local r2, g2 = front:getPixel(85, 45)
    self:check(
        quad and quad.visible and group:getLevel() == 1 and r > g * 3 and g2 > r2 * 3 and r + g2 > 0.1,
        'The billboard level is a quad with the image, shown upright and not mirrored'
    )
    local side = look(12, 0, -90)
    local sr, sg = side:getPixel(75, 45)
    local tr, tg = side:getPixel(85, 45)
    self:check(
        sr > sg * 3 and tg > tr * 3 and sr + tg > 0.1,
        'The billboard turns around the vertical axis to face the camera from any side'
    )
    group.rotation = { 0, 60, 0 }
    local turned = look(0, -12, 0)
    local ur, ug = turned:getPixel(75, 45)
    local vr, vg = turned:getPixel(85, 45)
    self:check(
        ur > ug * 3 and vg > vr * 3 and ur + vg > 0.1,
        'A turned group does not turn the billboard away from the camera'
    )
    group.billboardImage = ''
    group:update(0.1)
    self:check(world.byName.FarBillboard == nil, 'Clearing billboardImage removes the billboard level')
end

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local world = scene.world
    Plugins.activate(world, { 'lod' })
    local camera = world:create('Camera3D', { position = { 0, 0, -5 } })
    world:setCamera(camera)

    -- The quality profile scales the bias of every group.
    local group = world:create('LODGroup', { name = 'Pine', distances = { 10, 30, 80 } })
    local meshes = cubes(world, group, { 'PineHigh', 'PineMid', 'PineLow' })
    local plain = levelAt(group, world, camera, -7)
    world.lighting:applyQualityProfile('Low')
    local lowered = levelAt(group, world, camera, -7)
    world.lighting:applyQualityProfile('High')
    self:check(
        plain == 0 and lowered == 1 and Profiles.names[1] == 'Low'
            and world.lighting.render.lodBias == 1,
        'Quality profiles set Environment.render.lodBias, which lowers detail sooner on Low'
    )

    -- A zoomed-in lens counts as nearer; referenceFov = 0 turns that off.
    camera.fov = 40
    local zoomed = levelAt(group, world, camera, -15)
    group.referenceFov = 0
    local raw = levelAt(group, world, camera, -15)
    group.referenceFov = Plugins.require('lod').Select.defaultFov
    camera.fov = 84
    self:check(
        zoomed == 0 and raw == 1,
        'A narrow field of view keeps the detail of a nearer camera unless referenceFov is 0'
    )

    -- Shadows: only the levels up to shadowLevel cast.
    group.shadowLevel = 0
    group:update(0.1)
    local cast = { meshes[1].castShadow, meshes[2].castShadow, meshes[3].castShadow }
    group.shadowLevel = -1
    group:update(0.1)
    self:check(
        cast[1] and not cast[2] and not cast[3] and meshes[2].castShadow and meshes[3].castShadow,
        'shadowLevel limits shadow casting to the finer levels and -1 restores the authored values'
    )

    -- Cross-fade: both levels show while the new one comes in.
    local fader = world:create('LODGroup', { name = 'Fader', distances = { 10 }, fadeTime = 0.5 })
    local fades = cubes(world, fader, { 'FadeA', 'FadeB' })
    levelAt(fader, world, camera, -5)
    levelAt(fader, world, camera, -20)
    local start = fades[2].transparency
    fader:update(0.25)
    local middle = fades[2].transparency
    self:check(
        fades[1].visible and fades[2].visible and start > 0.7 and middle > 0.2 and middle < 0.8,
        'With fadeTime the old level stays while the new one fades in'
    )
    fader:update(0.5)
    self:check(
        not fades[1].visible and fades[2].visible and fades[2].transparency == 0
            and fades[1].transparency == 0,
        'When the fade ends the old level is hidden and the transparencies are as authored'
    )

    -- Animation rate per level on a skinned model sharing one skeleton.
    local path = 'validation/tests/fixtures/models/lod.glb'
    local model = Models.load(path, world.resources)
    local _, root = Models.instantiate(world, model, { name = 'Lab2' })
    local body = root:find('BodyLOD')
    local rate = model.animator.poseRate
    body.animationRates = '30, 12'
    body.forceLevel = 1
    body:update(0)
    local slow = model.animator.poseRate
    body.forceLevel = 0
    body:update(0)
    local fast = model.animator.poseRate
    body.animationRates = ''
    body:update(0)
    self:check(
        slow == 12 and fast == 30 and model.animator.poseRate == rate,
        'animationRates sets the Animator pose rate per level and an empty list restores it'
    )
    scene:release()

    checkBillboard(self)
end

return Module
