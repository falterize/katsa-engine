local Mesh = require('source.engine.composition.mesh')

-- Four ribbons on one stage:
--   * a red ball on a circle with a Single mode Trail3D (one node, always facing the camera),
--   * a blade swung through the air with a Dual mode trail between two plain nodes,
--   * a curved Beam3D between two posts whose texture scrolls (additive glow),
--   * a flat, shadow casting beam above the floor that also receives shadows.
local Lab = {}
Lab.__index = Lab

local function post(world, name, position, color)
    return Mesh.create(world, {
        name = name,
        size = { 0.6, 0.6, 0.6 },
        kind = 'sphere',
        color = color,
        position = position,
    })
end

function Lab.new(scene)
    local self = setmetatable({ scene = scene, time = 0 }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.sky.enabled = false
    world.environment.ambient = { 70, 78, 96 }
    Mesh.create(world, {
        name = 'Floor',
        position = { 0, -3, 0 },
        size = { 80, 6, 60 },
        surfaceAppearance = { colorMap = 'stone' },
    })
    world:create('DirectionalLight3D', {
        name = 'Sun',
        rotation = { 55, 30, 0 },
        color = { 255, 238, 210 },
        brightness = 1.1,
    })
    world.environment.shadows.enabled = true

    -- Single mode: the Trail3D is a child of the ball, so it needs no attachment at all.
    self.ball = Mesh.create(world, {
        name = 'Ball',
        kind = 'sphere',
        size = { 1, 1, 1 },
        color = { 1, 0.3, 0.2, 1 },
        position = { -6, 2, 0 },
    })
    self.single = world:create('Trail3D', {
        name = 'BallTrail',
        trailMode = 'Single',
        texture = 'assets/textures/particles/trail.png',
        width = 0.9,
        lifetime = 1.4,
        minLength = 0.15,
        color = { 1, 0.45, 0.25 },
        lightEmission = 0.8,
    }, self.ball)

    -- Dual mode: two plain nodes at the tip and the guard of a swinging blade.
    self.blade = world:create('Node3D', { name = 'Blade', position = { 6, 2, 0 } })
    Mesh.create(world, {
        name = 'BladeMesh',
        size = { 0.15, 3.2, 0.15 },
        color = { 0.8, 0.85, 0.95, 1 },
        position = { 0, 1.6, 0 },
    }, self.blade)
    local tip = world:create('Node3D', { name = 'Tip', position = { 0, 3.2, 0 } }, self.blade)
    local guard = world:create('Node3D', { name = 'Guard', position = { 0, 0.4, 0 } }, self.blade)
    self.dual = world:create('Trail3D', {
        name = 'BladeTrail',
        trailMode = 'Dual',
        attachment0 = tip,
        attachment1 = guard,
        faceCamera = false,
        texture = 'assets/textures/particles/trail.png',
        lifetime = 0.5,
        minLength = 0.05,
        color = { 0.55, 0.8, 1 },
        lightEmission = 1,
    })

    -- Beam: curved, texture repeats every 2 units and scrolls.
    local a = post(world, 'PostA', { -8, 4, -6 }, { 0.3, 0.6, 1, 1 })
    local b = post(world, 'PostB', { 8, 4, -6 }, { 0.3, 0.6, 1, 1 })
    -- The curve leaves along each node's X axis: turn the posts so it bows upward.
    a.rotation = { 0, 0, 90 }
    b.rotation = { 0, 0, 90 }
    self.beam = world:create('Beam3D', {
        name = 'EnergyBeam',
        attachment0 = a,
        attachment1 = b,
        width0 = 0.6,
        width1 = 1.4,
        curveSize0 = 7,
        curveSize1 = 7,
        segments = 24,
        texture = 'assets/textures/particles/beam.png',
        textureMode = 'Wrap',
        textureLength = 2,
        textureSpeed = -1.5,
        color = { 0.4, 0.85, 1 },
        lightEmission = 1,
    })

    -- A flat beam that lies in the world: it casts and receives shadows.
    local c = world:create('Node3D', { name = 'ShadeA', position = { -4, 3, 6 } })
    local d = world:create('Node3D', { name = 'ShadeB', position = { 4, 3, 6 } })
    self.shade = world:create('Beam3D', {
        name = 'ShadowBeam',
        attachment0 = c,
        attachment1 = d,
        width0 = 2,
        width1 = 2,
        faceCamera = false,
        castShadow = true,
        receiveShadow = true,
        lightInfluence = 1,
        color = { 0.9, 0.5, 0.9 },
        texture = 'assets/textures/particles/trail.png',
    })
    -- Align the flat strip: its face normal is the first node's Y axis.
    c.rotation = { 0, 0, 0 }

    scene.camera.position = { 0, 8, 17 }
    scene.camera.rotation = { -20, 180, 0 }
    return self
end

function Lab:update(dt)
    self.time = self.time + dt
    local t = self.time
    self.ball.position = { -6 + math.cos(t * 2.2) * 3.5, 2 + math.sin(t * 4.4) * 0.8, math.sin(t * 2.2) * 3.5 }
    self.blade.position = { 6, 2.5, 0 }
    self.blade.rotation = { 0, 0, math.sin(t * 3) * 80 }
    self.scene.world:updateNodes(dt)
end

return Lab
