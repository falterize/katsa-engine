-- Real-renderer integration; executed by the katsa shadow suite.
return function(test)
    local Resources = require('source.engine.core.resources')
    local World3D = require('source.engine.world.world')
    local Renderer = require('source.engine.graphics.pipeline.renderer')
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.shadows.enabled = true
    settings.shadows.resolution = 64
    settings.shadows.distance = 1000
    settings.shadows.visibleFacesOnly = false
    settings.lightSettings.cullInvisible = false
    local world = World3D.new(resources, settings)
    local camera = world:addCamera({ position = { 0, 30, -100 } })
    local renderer = Renderer.new(resources)
    world:create('Mesh3D', {
        name = 'CacheReceiver',
        position = { 150, -10, 10 },
        size = { 800, 4, 100 },
        castShadow = false,
    })
    local caster = world:create(
        'Mesh3D',
        { name = 'CacheCaster', position = { 0, 0, 10 }, size = { 4, 4, 4 } }
    )
    world:create('PointLight3D', { position = { 0, 10, 0 }, range = 40, castShadow = true })
    world:create(
        'SpotLight3D',
        { position = { 300, 10, 0 }, range = 40, radius = 20, castShadow = true }
    )

    local function draw()
        -- Make the next scan eligible without requesting a global forced rebuild.
        renderer.shadows.nextUpdate = -1
        renderer:draw(world, camera, 0)
        return renderer.shadows.updatedFaces
    end
    test:check(draw() == 7, 'Real renderer builds initial local shadow cache')
    local generation = renderer.shadows.generation
    test:check(
        draw() == 0 and renderer.shadows.generation == generation,
        'Real renderer reuses static depth atlas across eligible updates'
    )
    caster.position[1] = 2
    test:check(draw() == 6, 'Real renderer updates only the overlapping PointLight3D')
    caster.position[1] = 300
    test:check(draw() == 7, 'Real renderer invalidates old and new caster regions')
    caster.visible = false
    test:check(draw() == 1, 'Real renderer removes hidden caster shadow')
    caster.visible = true
    draw()
    caster.geometry.revision = (caster.geometry.revision or 0) + 1
    test:check(draw() == 1, 'Geometry revision updates the overlapping local source')
    local anchor = world:create('Node3D', { name = 'CacheParent', position = { 0, 0, 0 } })
    caster.parent = anchor
    draw()
    anchor.position[1] = -300
    test:check(draw() == 7, 'Parent motion invalidates old and new caster regions')
    anchor.visible = false
    test:check(draw() == 6, 'Inherited visibility removes the caster shadow')
    anchor.visible = true
    draw()
    anchor.position[1] = 0
    draw()
    caster:destroy()
    test:check(draw() == 1, 'Real renderer removes destroyed caster shadow')
    camera.position[1] = 20
    test:check(draw() == 0, 'Real renderer camera movement preserves local maps')
    settings.shadows.distance = 10
    draw()
    local disabled = true
    for _, record in ipairs(renderer.shadows.assignments) do
        disabled = disabled and renderer.shadows.lightData[record.light.slot][1] == -1
    end
    test:check(disabled, 'Real renderer disables maps outside global shadow distance')
    settings.shadows.distance = 1000
    draw()
    settings.shadows.maxUpdateFaces = 1
    for _, source in ipairs(world.lights) do
        source.shadowRevision = (source.shadowRevision or 0) + 1
    end
    local refreshed = draw()
    test:check(
        refreshed >= 1 and refreshed <= 6 and renderer.shadows.pendingFaces > 0,
        'Real renderer honors atomic source budget and reports deferred faces'
    )
    draw()
    test:check(renderer.shadows.pendingFaces == 0, 'Real renderer drains deferred source queue')
    renderer:release()
    world:release()
    resources:release()
end
