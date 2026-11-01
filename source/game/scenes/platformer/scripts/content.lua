local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs

local Lab = {}
Lab.__index = Lab

function Lab.new(scene)
    local self = setmetatable({ scene = scene, collected = 0, velocity = {}, state = '' }, Lab)
    local world = scene.world
    scene:createPhysics({ unitsPerMeter = 20, interpolate = true })
    world.physics = scene.physics
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    require('scene.scripts.lighting.directional').create(world).enabled = true
    require('scene.scripts.lighting.directional').create(world).brightness = 1.2
    world.environment.ambient = { 85, 100, 130 }
    world.environment.shadows.enabled = true
    world.environment.shadows.mode = 'Realistic'
    world.environment.shadows.maxUpdateFaces = 6
    world.environment.shadows.distance = 220
    scene.camera.drawDistance = 1600
    scene.package:require('scripts.builders.level').build(self)
    self.body = world:create('Body3D', {
        name = 'RunnerBody',
        position = { unpack(self.spawn) },
        rotationFactor = { 0, 0, 0 },
        friction = 0.2,
        autoSleep = false,
    })
    self.collider = world:create(
        'Collider3D',
        { name = 'RunnerCapsule', shape = 'Capsule', radius = 4, height = 24 },
        self.body
    )
    self.body:update(0)
    scene.character = require('source.engine.physics.3d.character').new(
        self.body.body,
        scene.camera,
        { radius = 4, height = 32, speed = 70, jumpSpeed = 112 }
    )
    world:setInteractionSource(self.body)
    self.avatarEffect = world:create('Shader3D', {
        name = 'RunnerEnergyShader',
        shaderPath = 'assets/shaders/examples/tint3D.glsl',
        uniforms = { tintEffect = { 1, 1, 1 } },
    }, self.body)
    self.rig = require('source.engine.import.models').load(
        'assets/models/characters/xbot.glb',
        scene.resources
    )
    require('source.engine.import.models').instantiate(world, self.rig, {
        name = 'RunnerRig',
        parent = self.avatarEffect,
        position = { 0, -16, 0 },
        scale = { 0.16, 0.16, 0.16 },
    })
    require('scene.scripts.animation.proceduralClips').add(self.rig)
    local sourceClips = {}
    for _, clip in ipairs(self.rig.animations) do
        sourceClips[clip.name] = clip
    end
    for name, source in pairs({ Dash = 'Demo Run', Slide = 'Demo Walk' }) do
        local clip = sourceClips[source]
        self.rig.animations[#self.rig.animations + 1] = {
            name = 'Demo ' .. name,
            duration = clip.duration,
            channels = clip.channels,
            markers = {},
        }
    end
    self.animator = self.rig.animator
    self.burst = world:create('ParticleEmitter3D', {
        name = 'AbilityBurst',
        rate = 0,
        maxParticles = 160,
        lifetime = { 0.15, 0.4 },
        speed = { 15, 45 },
        spread = 180,
        startSize = { 1, 2 },
        gravityScale = 0.1,
        unlit = true,
    }, self.body)
    self.trail = world:create('ParticleEmitter3D', {
        name = 'DashTrail',
        rate = 0,
        maxParticles = 180,
        lifetime = { 0.15, 0.35 },
        speed = { 0, 2 },
        startSize = { 1, 2 },
        unlit = true,
    }, self.body)
    local focus =
        world:create('Attachment3D', { name = 'CameraFocus', position = { 0, 10, 0 } }, self.body)
    scene.camera.position = { 0, 45, -110 }
    scene.camera.rotation = { -10, 0, 0 }
    self.camera = require('source.engine.cameras.controller').new(scene.camera, {
        mode = 'ThirdPerson',
        target = focus,
        distance = 65,
        physics = scene.physics,
        filter = scene.character.rayFilter,
        positionSmooth = 14,
    })
    self.camera:update(0, true)
    self.abilities = scene.package:require('scripts.behaviors.abilities').new(self)
    scene.physics.beforeStep = function(_, dt)
        self.abilities:step(dt)
    end
    local actions = scene.input.actions
    actions:define('Dash', { key = 'lshift' })
    actions:define('Slide', { key = 'c' })
    actions:on('Jump', function()
        if not scene.freeDebugCamera then
            self.abilities:jump()
        end
    end)
    actions:on('Dash', function()
        if not scene.freeDebugCamera then
            self.abilities:dash()
        end
    end)
    actions:on('Slide', function()
        if not scene.freeDebugCamera then
            self.abilities:slide()
        end
    end)
    self.blur = scene.ui:create('Shader2D', {
        name = 'SpeedBlur',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        zIndex = -100,
        backgroundTransparency = 1,
        shaderTransparency = 1,
        shaderPath = 'assets/shaders/examples/speedBlur.glsl',
        affects3D = true,
        uniforms = { strength = 0 },
    }, scene.ui.content)
    return self
end

function Lab:respawn()
    self.body.body:teleport({ unpack(self.spawn) })
    self.body.body:setVelocity({ 0, 0, 0 })
    self.abilities.dashTime = 0
    self.abilities.slideTime = 0
    self.collider.height = 24
    self.scene.character.height = 32
    self.rig.root.position[2] = -16
    self.rig.root.rotation[1] = 0
end

function Lab:update(dt)
    local scene = self.scene
    if self.controlsPanel then
        self.controlsPanel.size = {
            0,
            math.min(245, scene.ui.width - 24),
            0,
            math.min(180, math.max(36, scene.ui.height * 0.66 - 165)),
        }
    end
    scene.physics:update(dt)
    local v = self.body.body:getVelocity(self.velocity)
    local speed = math.sqrt(v[1] ^ 2 + v[3] ^ 2)
    local c = scene.character
    local state = c.grounded and (speed > 100 and 'Run' or speed > 5 and 'Walk' or 'Idle')
        or (v[2] > 0 and 'Jump' or 'Fall')
    if self.abilities.dashTime > 0 then
        state = 'Dash'
    elseif self.abilities.slideTime > 0 then
        state = 'Slide'
    end
    if state ~= self.state then
        self.state = state
        self.animator:transition('Demo ' .. state, 0.15)
    end
    if speed > 3 then
        self.rig.root.rotation[2] = -math.deg(math.atan2(v[1], v[3]))
    end
    local tint = self.avatarEffect.uniforms.tintEffect
    tint[1], tint[2], tint[3] =
        self.abilities.dashTime > 0 and 0.65 or 1,
        self.abilities.dashTime > 0 and 1.2 or 1,
        self.abilities.dashTime > 0 and 1.6 or 1
    self.trail.rate = self.abilities.dashTime > 0 and 100
        or self.abilities.slideTime > 0 and 45
        or 0
    self.blur.uniforms.strength = math.min(0.06, math.max(0, (speed - 85) / 2400))
    self.blur.shaderTransparency = speed > 85 and 0 or 1
    local p = self.body.position
    for i, pickup in ipairs(self.pickups) do
        if not pickup.collected then
            local q = pickup.mesh.position
            if (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2 < 22 ^ 2 then
                pickup.collected = true
                pickup.mesh:destroy()
                self.collected = self.collected + 1
                self.spawn = { pickup.position[1], pickup.position[2] + 24, pickup.position[3] }
                self.burst:emit(40)
                scene.audio:play('assets/audio/effects/chime.wav', { volume = 0.25 })
            end
        end
    end
    if p[2] < -100 then
        self:respawn()
    end
    scene.world:updateNodes(dt)
    if self.status then
        self.status.text = string.format(
            'Crystals %d/%d | %s | Speed %.0f',
            self.collected,
            #self.pickups,
            state,
            speed
        )
    end
end

return Lab
