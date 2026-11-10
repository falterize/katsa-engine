local Array = require('../math.array')
local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local Sim = require('./simulation')
local V = require('../core.validate')
local Brightness = require('../components.rendering.brightness')

local Settings = require('./settings')

local S = {}
S.__index = function(self, key)
    if Settings.keys[key] then
        return self.settings[key]
    end
    return S[key]
end
S.__newindex = function(self, key, value)
    if Settings.keys[key] then
        self.settings[key] = value
    else
        rawset(self, key, value)
    end
end

function S.new(world, dimension)
    return setmetatable({
        world = world,
        settings = world.environment and world.environment.particles
            or Settings.create(dimension or 3),
        dimension = dimension or 3,
        emitters = {},
        accumulator = 0,
        stats = { live = 0, dropped = 0, collisionQueries = 0, steps = 0 },
        rayStart = {},
        rayEnd = {},
        hit = {},
        filter = function(body)
            return body.canCollide and not body.isTrigger
        end,
    }, S)
end

function S:add(e)
    self.emitters[#self.emitters + 1] = e
end

function S:remove(e)
    e:clear()
    e.pool = {}
    if e._particleMesh then
        e._particleMesh:release()
        e._particleMesh = nil
    end
    if e._spriteBatch then
        e._spriteBatch:release()
        e._spriteBatch = nil
    end
    if e._particleQuad then
        e._particleQuad:release()
        e._particleQuad = nil
    end
    e._vertices, e._renderOrder = nil, nil
    for i, item in ipairs(self.emitters) do
        if item == e then
            table.remove(self.emitters, i)
            break
        end
    end
end

function S:physics()
    return self.dimension == 2 and self.world.physics2D or self.world.physics
end

function S:visibility()
    return self.dimension == 2 and require('source.engine.particles.2d.visibility')
        or require('source.engine.particles.3d.visibility')
end

function S:validate(e)
    if self:physics() then
        local groups = self:physics().collisionGroups
        if not groups.bits[e.collisionGroup] then
            e.collisionGroup = 'Default'
        end
    end
    local defaults = require('source.engine.nodes.core.baseNode').getClass(
        self.dimension == 2 and 'ParticleEmitter2D' or 'ParticleEmitter3D'
    ).defaults
    local snapshot = e._configSnapshot
    local changed = not snapshot
    if snapshot then
        for key in pairs(defaults) do
            if key ~= 'liveCount' then
                local value, old = e[key], snapshot[key]
                if Array.is(value) then
                    if not Array.is(old) or #old ~= #value then
                        changed = true
                        break
                    end
                    for i = 1, #value do
                        if old[i] ~= value[i] then
                            changed = true
                            break
                        end
                    end
                elseif old ~= value then
                    changed = true
                    break
                end
            end
        end
    end
    if not changed then
        return
    end
    Brightness.check(e.brightness, 'ParticleEmitter3D')
    for _, key in ipairs({ 'rate', 'drag', 'maxDistance', 'attractionRange', 'attractionStrength' }) do
        V.number(e[key], 'ParticleEmitter3D.' .. key, 0)
    end
    V.number(e.attractionSoftening, 'ParticleEmitter3D.attractionSoftening', 0.001)
    V.number(e.gravityScale, 'ParticleEmitter3D.gravityScale')
    V.number(e.seed, 'ParticleEmitter3D.seed', 0, 2147483647)
    V.number(e.maxParticles, 'ParticleEmitter3D.maxParticles', 0, 16384)
    if self.dimension == 3 then
        V.number(e.shadowMaxParticles, 'ParticleEmitter3D.shadowMaxParticles', 0, 16384)
        V.number(e.shadowAlphaCutoff, 'ParticleEmitter3D.shadowAlphaCutoff', 0, 1)
    end
    V.number(e.spread, 'ParticleEmitter3D.spread', 0, 180)
    for _, key in ipairs({ 'lifetime', 'speed', 'startSize', 'startRotation', 'angularSpeed' }) do
        V.vector(e[key], 'ParticleEmitter3D.' .. key, 2)
        assert(e[key][2] >= e[key][1], key .. ' range must be ordered')
    end
    assert(
        e.lifetime[1] > 0 and e.startSize[1] >= 0 and e.speed[1] >= 0,
        'Lifetime must be positive; size/speed nonnegative'
    )
    for _, key in ipairs({
        'direction',
        'shapeSize',
        'acceleration',
        'gravity',
        'attractionPoint',
        'axisRight',
        'axisUp',
    }) do
        V.vector(e[key], e.className .. '.' .. key, self.dimension)
    end
    for i = 1, self.dimension do
        assert(e.shapeSize[i] >= 0, 'Particle shape size must be nonnegative')
    end
    if e.orientation == 'Axes' and self.dimension == 3 then
        local r, u = e.axisRight, e.axisUp
        local x, y, z =
            r[2] * u[3] - r[3] * u[2], r[3] * u[1] - r[1] * u[3], r[1] * u[2] - r[2] * u[1]
        assert(x * x + y * y + z * z > 1e-10, 'Particle axes must be nonzero and independent')
    end
    V.vector(e.atlasGrid, 'atlasGrid', 2)
    assert(
        e.atlasGrid[1] >= 1
            and e.atlasGrid[2] >= 1
            and e.atlasGrid[1] % 1 == 0
            and e.atlasGrid[2] % 1 == 0,
        'Atlas grid must use positive integers'
    )
    V.number(e.atlasFPS, 'atlasFPS', 0)
    V.number(e.restitution, 'restitution', 0, 1)
    V.number(e.collisionFriction, 'collisionFriction', 0, 1)
    for key, choices in pairs({
        shape = self.dimension == 2 and { 'Point', 'Box', 'Disc', 'Line' }
            or { 'Point', 'Box', 'Sphere', 'Disc', 'Cylinder' },
        simulationSpace = { 'Local', 'World' },
        orientation = { 'Camera', 'Velocity', 'Axes' },
        blendMode = { 'Alpha', 'Add', 'Multiply' },
        disabledBehavior = { 'Drain', 'Clear' },
        offscreenBehavior = { 'Pause', 'Simulate' },
        collisionResponse = { 'Bounce', 'Kill' },
    }) do
        local valid = false
        for _, choice in ipairs(choices) do
            if e[key] == choice then
                valid = true
            end
        end
        assert(valid, 'Invalid particle ' .. key)
    end
    snapshot = snapshot or {}
    e._configSnapshot = snapshot
    for key in pairs(defaults) do
        if key ~= 'liveCount' then
            local value = e[key]
            if Array.is(value) then
                local old = snapshot[key] or {}
                snapshot[key] = old
                for i = 1, #value do
                    old[i] = value[i]
                end
            else
                snapshot[key] = value
            end
        end
    end
end

function S:emit(e, count)
    if e._adorneeLost then
        return 0
    end
    V.number(count, 'emit(count)', 0, 1000000)
    assert(count % 1 == 0, 'emit(count) requires an integer')
    self:validate(e)
    local total = 0
    for _, item in ipairs(self.emitters) do
        total = total + #item.particles
    end
    local allowed = math.min(
        count,
        math.max(0, math.floor(e.maxParticles) - #e.particles),
        math.max(0, self.maxParticles - total)
    )
    if e._seed ~= e.seed then
        e:setSeed(e.seed)
    end
    for i = 1, allowed do
        Sim.spawn(e)
    end
    e.liveCount = #e.particles
    self.stats.dropped = self.stats.dropped + count - allowed
    return allowed
end

function S:update(dt)
    V.number(self.maxParticles, 'Particles.maxParticles', 0, 16384)
    V.number(self.collisionBudget, 'Particles.collisionBudget', 0, 1024)
    V.number(self.maxSteps, 'Particles.maxSteps', 1, 8)
    assert(
        self.maxSteps % 1 == 0 and self.collisionBudget % 1 == 0,
        'Particle budgets require integer values'
    )
    V.vector(self.wind, 'Particles.wind', self.dimension)
    if dt <= 0 then
        return
    end
    local start = katsa.timer.getTime()
    self.accumulator = math.min(self.accumulator + dt, self.fixedDelta * self.maxSteps)
    self.stats.collisionQueries, self.stats.steps = 0, 0
    local camera
    if self.dimension == 2 then
        camera = self.world.currentCamera
    else
        camera = self.world.root.currentCamera
    end
    self.visibilityCamera = camera
    if camera and self.dimension == 3 then
        camera:update(
            camera.width or katsa.graphics.getWidth(),
            camera.height or katsa.graphics.getHeight()
        )
    end
    self.stats.pausedEmitters = 0
    for _, e in ipairs(self.emitters) do
        self:validate(e)
        if self.dimension == 3 then
            self.world:resolveLayerGroup(e)
        end
        e._simulationPaused = e.offscreenBehavior == 'Pause'
            and not self:visibility().relevant(e, camera)
        if e._simulationPaused then
            self.stats.pausedEmitters = self.stats.pausedEmitters + 1
        end
    end
    while self.accumulator >= self.fixedDelta do
        self.accumulator = self.accumulator - self.fixedDelta
        self.stats.steps = self.stats.steps + 1
        -- Rotate emitter order so the shared collision budget does not always favor emitter #1.
        local n = #self.emitters
        self.cursor = n > 0 and ((self.cursor or 0) % n) + 1 or 1
        for j = 0, n - 1 do
            Sim.step(self, self.emitters[(self.cursor + j - 1) % n + 1], self.fixedDelta)
        end
    end
    self.stats.live = 0
    for _, e in ipairs(self.emitters) do
        self.stats.live = self.stats.live + #e.particles
    end
    self.stats.updateMilliseconds = (katsa.timer.getTime() - start) * 1000
end

function S:draw(camera, emitter)
    if self.dimension == 2 then
        return require('source.engine.particles.2d.renderer').draw(self)
    end
    return require('source.engine.particles.3d.renderer').draw(self, camera, emitter)
end

return S
