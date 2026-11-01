return function(test)
    local Lights = require('source.engine.world.lights')
    local lights = Lights.new()
    local a = {
        enabled = true,
        range = 100,
        radius = 5,
        color = { 255, 255, 255 },
        brightness = 1,
        rotation = { 0, 0, 0 },
        type = 'PointLight3D',
        worldPosition = { 0, 0, 0 },
        worldDirection = { 0, 0, 1 },
    }
    local b = {
        enabled = true,
        range = 100,
        radius = 5,
        color = { 255, 255, 255 },
        brightness = 1,
        rotation = { 0, 0, 0 },
        type = 'PointLight3D',
        worldPosition = { 100, 0, 0 },
        worldDirection = { 0, 0, 1 },
    }
    for _, light in ipairs({ a, b }) do
        light.getWorldPosition = function(self)
            return self.worldPosition
        end
        light.getRenderWorldPosition = light.getWorldPosition
        light.getWorldMatrix = function()
            return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
        end
        light.getRenderWorldMatrix = light.getWorldMatrix
    end
    local settings = {
        maxActiveLights = 2,
        selectionHz = 10,
        selectionBias = 0,
        cullInvisible = false,
        nearDistance = 100,
        nearUpdateHz = 60,
        farUpdateHz = 10,
    }
    local world = { lights = { a, b }, lighting = { lightSettings = settings } }
    local camera = { position = { 0, 0, 0 } }
    lights:update(world, camera, {}, 0)
    local first, second = lights.selected[1], lights.selected[2]
    camera.position[1] = 100
    lights:update(world, camera, {}, 1)
    test:check(
        lights.selected[1] == first and lights.selected[2] == second and a.slot == 1 and b.slot == 2,
        'Camera3D distance reordering preserves selected-light slots'
    )
    settings.maxActiveLights = 1
    lights:update(world, camera, {}, 2)
    test:check(
        lights.selected[1] == b and #lights.selected == 1 and b.slot == 1,
        'Selection limits still choose the nearest eligible source'
    )
    settings.maxActiveLights = 2
    lights:update(world, camera, {}, 3)
    test:check(
        lights.selected[1] == b and lights.selected[2] == a and a.slot == 2,
        'New winners append without reordering retained sources'
    )
    b.enabled = false
    lights:update(world, camera, {}, 4)
    test:check(
        #lights.selected == 1 and lights.selected[1] == a and a.slot == 1,
        'Removed sources compact selected slots correctly'
    )
    local reused = Lights.new()
    a.enabled, b.enabled = true, true
    a.selected, b.selected = false, false
    a.slot, b.slot = nil, nil
    a.nextUpdate, b.nextUpdate = nil, nil
    settings.maxActiveLights = 1
    settings.nearUpdateHz, settings.farUpdateHz = 0.01, 0.01
    camera.position[1] = 0
    reused:update(world, camera, {}, 0)
    camera.position[1] = 100
    reused:update(world, camera, {}, 1)
    camera.position[1] = 0
    reused:update(world, camera, {}, 2)
    test:check(
        reused.selected[1] == a and reused.position[1][1] == 0,
        'Returning light refreshes a reused uniform slot despite its cached update timer'
    )
end
