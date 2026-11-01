local T = {}

local function fixture(name)
    return assert(loadstring(katsa.filesystem.read('validation/tests/fixtures/v100-' .. name .. '.lua')))()
end

local function sampling(test)
    local Pose, old = require('source.engine.animation.skeleton.pose'), fixture('pose')
    for _, method in ipairs({ 'LINEAR', 'STEP', 'CUBICSPLINE' }) do
        for _, target in ipairs({ 'translation', 'rotation' }) do
            local channel = { times = {}, values = {}, method = method, target = target }
            local width = target == 'rotation' and 4 or 3
            for i = 1, 96 do
                channel.times[i] = { i / 30 }
                for j = 1, (method == 'CUBICSPLINE' and 3 or 1) do
                    local value = {}
                    for k = 1, width do
                        value[k] = math.sin(i + k + j) * 0.2
                    end
                    if width == 4 then
                        value[4] = 1
                    end
                    channel.values[#channel.values + 1] = value
                end
            end
            for i = 1, 600 do
                -- Forward playback, reverse, shared-track seeks, endpoints, live keys.
                local time = i < 300 and i / 180 or (i % 71) / 21
                if i == 400 then
                    for _, key in ipairs(channel.times) do
                        key[1] = key[1] + 0.01
                    end
                end
                local expected, actual = old.sample(channel, time), Pose.sample(channel, time)
                for j = 1, width do
                    assert(expected[j] == actual[j], 'Key interval changed interpolation')
                end
            end
        end
    end
    test:check(
        true,
        'Interval hints preserve 3600 exact samples, seeks, reverse playback and live key edits'
    )
    local M, reference = require('source.engine.math.math3d'), fixture('math3d')
    local V = require('source.engine.math.vector3')
    for i = 1, 80 do
        local p, r, s = V.new(i / 7, -i, 2), V.new(i * 3, -i / 2, i), V.new(1 + i / 90, 2, 0.5)
        for _, kind in ipairs({ 'compose', 'trs' }) do
            local rotation = kind == 'trs' and { 0.1, 0.2, 0.3, 0.9 } or r
            local a, b = M[kind](p, rotation, s), reference[kind](p, rotation, s)
            for j = 1, 16 do
                assert(a[j] == b[j], 'Transform scale caching changed arithmetic')
            end
        end
    end
    test:check(
        true,
        'Managed-scale Euler and quaternion transforms remain byte-exact to v100 arithmetic'
    )
end

local function mixer(test)
    local update = require('source.engine.nodes.animation.animator').update
    local reference = fixture('mixer')

    local function instance(count, masked)
        local node = {
            name = 'Bone',
            translation = {},
            rotation = {},
            scale = {},
            rest = {
                translation = { 1, 2, 3 },
                rotation = { 0.1, 0.2, 0.3, 0.9 },
                scale = { 1, 2, 1 },
            },
        }
        local animator =
            { tracks = {}, poseRate = 60, model = { nodes = { node }, update = function() end } }
        for i = 1, count do
            local lookup = {}
            if i % 2 == 0 then
                lookup.scale = {
                    target = 'scale',
                    method = 'LINEAR',
                    times = { { 0 }, { 1 } },
                    values = {
                        { 1, 1, 1 },
                        { 2, 3, 4 },
                    },
                }
            end
            animator.tracks[i] = {
                advance = function() end,
                enabled = true,
                state = 'Playing',
                _blendWeight = 0.7,
                boneMask = masked and { Bone = 0 } or {},
                order = 0,
                timePosition = 0.3,
                _buffers = {},
                clip = { _lookup = { [node] = lookup } },
            }
        end
        return animator, node
    end
    for count = 0, 3 do
        for _, masked in ipairs({ false, true }) do
            local a, an = instance(count, masked)
            local b, bn = instance(count, masked)
            for frame = 1, 20 do
                reference(a, 1 / 60)
                update(b, 1 / 60)
                for _, path in ipairs({ 'translation', 'rotation', 'scale' }) do
                    for i = 1, #an[path] do
                        assert(
                            an[path][i] == bn[path][i],
                            'Rest-pose mixer shortcut changed blending'
                        )
                    end
                end
            end
        end
    end
    test:check(
        true,
        'Mixer rest paths preserve exact normalized poses with zero/one/multiple tracks and masks'
    )
end

local function lights(test)
    local Lights, reference = require('source.engine.world.lights'), fixture('lights')
    local V, C = require('source.engine.math.vector3'), require('source.engine.math.color')

    local function world()
        local w = {
            lights = {},
            lighting = {
                lightSettings = {
                    maxActiveLights = 8,
                    selectionHz = 11,
                    cullInvisible = false,
                    nearDistance = 200,
                    nearUpdateHz = 30,
                    farUpdateHz = 7,
                    selectionBias = 0.1,
                    selectionHoldSeconds = 0.4,
                },
            },
        }
        for i = 1, 12 do
            local kind = ({ 'DirectionalLight3D', 'PointLight3D', 'SpotLight3D' })[i % 3 + 1]
            w.lights[i] = {
                type = kind,
                worldPosition = V.new(i * 35, 2, 10),
                worldDirection = V.new(0, 0, 1),
                color = C.new(100 + i, 90, 255),
                range = 180,
                radius = 30,
                brightness = 2,
                rainbow = i % 2 == 0,
                enabled = true,
                isVisible = function(self)
                    return self.visible ~= false
                end,
                _preparedLightPose = true,
            }
        end
        return w
    end
    local a, b = world(), world()
    local old, new = reference.new(), Lights.new()
    local camera = { position = V.new(0, 0, 0) }
    local deps = { meshSnapshots = true, nodes = {} }
    for _, w in ipairs({ a, b }) do
        for _, l in ipairs(w.lights) do
            deps.nodes[l] = { chainChanged = false }
        end
    end
    for frame = 1, 180 do
        camera.position.X = math.sin(frame / 11) * 200
        for _, w in ipairs({ a, b }) do
            local l = w.lights[frame % 12 + 1]
            l.worldPosition.Y = frame % 19
            l.color.R = frame % 255
            l.rainbow = frame % 3 == 0
            l.visible = frame % 13 ~= 0
            l.enabled = frame % 17 ~= 0
            l.brightness = frame % 7
            if frame % 11 == 0 then
                l.forceUpdate = true
            else
                l.forceUpdate = false
            end
        end
        old:update(a, camera, {}, frame / 60, deps)
        new:update(b, camera, {}, frame / 60, deps)
        assert(
            old.count == new.count
                and old.pending == new.pending
                and old.pendingUntil == new.pendingUntil,
            'Light selection or update deadlines changed'
        )
        for _, key in ipairs({ 'position', 'direction', 'color', 'extra' }) do
            for i = 1, new.count do
                for j = 1, 4 do
                    assert(old[key][i][j] == new[key][i][j], 'Light uniform changed')
                end
            end
        end
    end
    test:check(
        true,
        'Flat light inputs preserve all light types, GPU slots, named writes and pending deadlines'
    )
    for _, light in ipairs({ old.selected[1], new.selected[1] }) do
        light.radius = 'invalid'
        light.forceUpdate = true
    end
    for attempt = 1, 2 do
        local okOld = pcall(old.update, old, a, camera, {}, 4, deps)
        local okNew = pcall(new.update, new, b, camera, {}, 4, deps)
        assert(not okOld and not okNew, 'Invalid light inputs stopped retrying after an error')
    end
    test:check(true, 'Failed light preparation retains invalidation and retries like v100')
end

local function physics(test)
    local scene =
        assert(test.manager:switch(require('source.game.runtime.game').new, 'animationPhysicsLab'))
    local w = scene.world
    local node = w:create('Body3D', { bodyType = 'Static' })
    local a =
        w:create('Collider3D', { size = require('source.engine.math.vector3').new(3, 4, 5) }, node)
    node:update(0)
    local collider = node.body.settings.collider
    local keys, descriptors = node._colliderKeys, node._colliderDescriptors
    for i = 1, 12 do
        node:update(0)
    end
    test:check(
        node.body.settings.collider == collider
            and node._colliderKeys == keys
            and node._colliderDescriptors == descriptors,
        'Unchanged bodies reuse collider scratch and preserve persistent descriptors'
    )
    a.size.X = 9
    node:update(0)
    test:check(
        node.body.settings.collider ~= collider
            and collider.children[1].size[1] == 3
            and node.body.settings.collider.children[1].size[1] == 9,
        'Named collider writes rebuild without mutating previous descriptors'
    )
    local valid = node.body.settings.collider
    a.size.X = -1
    local first = pcall(node.update, node, 0)
    local second = pcall(node.update, node, 0)
    test:check(
        not first and not second and node.body.settings.collider == valid,
        'Invalid collider changes preserve live shapes and are retried until corrected'
    )
    a.size.X = 9
    node:update(0)
    local holder = w:create('Body3D', { bodyType = 'Static' })
    a.parent = holder
    node:update(0)
    holder:update(0)
    test:check(
        #node._colliderDescriptors == 0 and #holder._colliderDescriptors == 1,
        'Reparented colliders release former body scratch references'
    )
    a:destroy()
    holder:update(0)
    test:check(
        #holder._colliderDescriptors == 0,
        'Destroyed colliders are removed from body scratch'
    )
    local p = w.physics
    p.pendingColliderChanges, p.pendingSettings, p.pendingPoses = nil, nil, nil
    for i = 1, 8 do
        p:flushBodyChanges()
    end
    test:check(
        p.pendingColliderChanges == nil and p.pendingSettings == nil and p.pendingPoses == nil,
        'Idle physics flushes allocate no deferred-operation arrays'
    )
    local order = {}
    local body = {
        set = function(self, values)
            order[#order + 1] = values.id
            if values.id == 1 then
                p.pendingSettings = { { body = self, values = { id = 3 } } }
            end
        end,
    }
    p.pendingSettings =
        { { body = body, values = { id = 1 } }, { body = body, values = { id = 2 } } }
    p:flushBodyChanges()
    assert(
        table.concat(order, ',') == '1,2' and #p.pendingSettings == 1,
        'Reentrant request was consumed too early'
    )
    p:flushBodyChanges()
    test:check(
        table.concat(order, ',') == '1,2,3',
        'Deferred setting callbacks retain next-flush ordering'
    )
    local raw = node.body.raw
    raw:getTransformTo(p.transform)
    p.transform:getRotationTo(p.rotation)
    local expected = {
        p.rotation.e00,
        p.rotation.e01,
        p.rotation.e02,
        p.rotation.e10,
        p.rotation.e11,
        p.rotation.e12,
        p.rotation.e20,
        p.rotation.e21,
        p.rotation.e22,
    }
    raw:getRotationTo(p.rotation)
    local actual = {
        p.rotation.e00,
        p.rotation.e01,
        p.rotation.e02,
        p.rotation.e10,
        p.rotation.e11,
        p.rotation.e12,
        p.rotation.e20,
        p.rotation.e21,
        p.rotation.e22,
    }
    for i = 1, 9 do
        assert(expected[i] == actual[i])
    end
    test:check(true, 'Direct solver rotation reads match the former intermediate transform copy')
end

function T.new(manager)
    local base = require('validation.tests.versions.v100.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        sampling(test)
        mixer(test)
        lights(test)
        physics(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v101 regression/integration checks')
    end
    return base
end

return T
