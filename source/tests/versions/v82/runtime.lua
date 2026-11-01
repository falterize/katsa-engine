local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED v82 ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:update() end

function T:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS ' .. label)
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    require('source.tests.integration.shadowCacheRuntime')(self)
    local scene = self.manager:switch(require('source.game.runtime.game').new, 'shadows')
    local world, renderer, camera = scene.world, scene.renderer, scene.camera
    local environment = world.environment
    local Tree = require('source.engine.editor.tree.traversal')
    local debugRow, oldGizmos
    for _, row in ipairs(Tree.children(environment)) do
        if row.name == 'Debug' then
            debugRow = row
        end
        if row.name == 'Gizmos' then
            oldGizmos = row
        end
    end
    self:check(
        debugRow and not oldGizmos,
        'EnvironmentLighting exposes debug instead of top-level gizmos'
    )
    self:check(
        Tree.children(debugRow)[1]._editorTarget == environment.debug.gizmos,
        'Debug contains editable gizmos settings'
    )
    local fields = {}
    for _, field in
        ipairs(require('source.engine.editor.inspectors.properties').list(environment.debug))
    do
        fields[field.key] = field
    end
    self:check(fields.bones and fields.wireframe, 'Debug exposes bone and wireframe toggles')
    world.debug = { wireframe = false, bones = false }
    self:check(
        world.debug == environment.debug and environment.gizmos == environment.debug.gizmos,
        'Previous world.debug and gizmos API remain synchronized'
    )
    environment.debug.gizmos.enabled = false
    environment.render.frameCache = false
    environment.shadows.sourceFadeSeconds = 0
    environment.shadows.maxUpdateFaces = 195
    environment.shadows.visibleFacesOnly = false
    local directional = scene.demo.directionalShadow
    self:check(
        directional and directional:isA('DirectionalLight3D') and not directional.enabled,
        'Shadows lab exposes the existing disabled DirectionalSun node'
    )
    directional.enabled = true
    directional.shadowGroup = 'SunOnly'
    world.layerGroups:add('SunOnly')
    world.layerGroups:add('Blocker')
    local blocker = world:create('Mesh3D', {
        name = 'GroupBlocker',
        shadowGroup = 'Blocker',
        layerGroup = 'Blocker',
        position = { 0, 20, 50 },
        size = { 20, 20, 20 },
    })
    local function draw()
        renderer.shadows.nextUpdate = -1
        renderer:draw(world, camera, 1, true)
    end
    draw()

    local function contains(list)
        for _, object in ipairs(list) do
            if object == blocker then
                return true
            end
        end
        return false
    end
    self:check(
        world.lighting._directionalSun.shadowGroup == 'SunOnly'
            and contains(renderer.shadows.sunCasters),
        'Directional node propagates its shadow group'
    )
    world.layerGroups:set('SunOnly', 'Blocker', false)
    draw()
    self:check(
        renderer.shadows.updatedSun and not contains(renderer.shadows.sunCasters),
        'Sun group exclusions remove blockers and invalidate cached cascades'
    )
    world.layerGroups:set('SunOnly', 'Blocker', true)
    draw()
    self:check(
        contains(renderer.shadows.sunCasters),
        'Restored sun group interaction rebuilds cascades'
    )
    local Models = require('source.engine.import.models')
    local rig = Models.load('assets/models/characters/xbot.glb', scene.resources)
    Models.instantiate(
        world,
        rig,
        { name = 'ShadowRig', position = { 0, 0, 50 }, scale = { 0.2, 0.2, 0.2 } }
    )
    require('source.game.shared.models.proceduralClips').add(rig)
    draw()
    local hasSkin = false
    for _, object in ipairs(renderer.shadows.sunCasters) do
        hasSkin = hasSkin or object.skin ~= nil
    end
    self:check(
        hasSkin and renderer.stats.shadowTriangles > 0,
        'Real skinned model participates in shadow rasterization'
    )
    draw()
    self:check(renderer.shadows.updatedFaces == 0, 'Static skeleton reuses shadow maps')
    rig.animator:transition('Demo Walk', 0)
    rig.animator:update(0.2)
    draw()
    self:check(renderer.shadows.updatedSun, 'Animated bone pose invalidates solar shadows')
    environment.shadows.maxUpdateFaces = 1
    environment.shadows.resolution = 128
    draw()
    self:check(
        renderer.shadows.updatedFaces > 1 and renderer.shadows.pendingFaces == 0,
        'Atlas reallocation rebuilds required sources together instead of exposing empty queued tiles'
    )
    -- Sampling probe must submit new frames despite a valid static frame cache.
    environment.render.frameCache = true
    -- Count actual canvas draws instead of renderer calls, which could reuse a cached image.
    local frame = renderer.frame
    local result =
        require('source.engine.graphics.debug.shadowProbe').measure(renderer, world, camera, 1, 1)
    self:check(
        renderer.frame >= frame + 6 and result.withRebuild and result.includesReadback,
        'Shadow A/B probe submits both sampling modes and a forced rebuild mode'
    )
    self:check(
        environment.render.frameCache
            and not renderer.freezeShadowUpdates
            and not renderer.shadows.samplingDisabled,
        'Probe restores rendering options'
    )
    print(
        'SHADOW_PROBE',
        result.withoutSampling,
        result.withSampling,
        result.withRebuild,
        result.difference,
        result.buildDifference,
        result.buildCPUMilliseconds
    )
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' lighting/debug checks')
    katsa.event.quit()
end

return T
