local ipairs = require('source.engine.math.array').ipairs
local add = require('./builders.object')

local Demo = {}
Demo.__index = Demo

function Demo.new(scene)
    local self = setmetatable(
        { scene = scene, items = {}, serial = 0, running = false, elapsed = 0, limit = 150 },
        Demo
    )
    scene.showStats = false
    scene:createPhysics()
    scene.camera.position = { 0, 100, -200 }
    scene.camera.rotation = { -18, 0, 0 }
    scene.camera.drawDistance = 1000
    scene.world.environment.fog.enabled = false
    scene.world.environment.debug.gizmos.enabled = false
    scene.world.environment.ambient = { 170, 185, 200 }
    local walls = {
        { 'BoxFloor', { 0, -4, 50 }, { 120, 8, 120 } },
        { 'BoxLeft', { -64, 32, 50 }, { 8, 72, 136 } },
        { 'BoxRight', { 64, 32, 50 }, { 8, 72, 136 } },
        { 'BoxBack', { 0, 32, 114 }, { 120, 72, 8 } },
        { 'BoxFront', { 0, 6, -14 }, { 120, 12, 8 } },
    }
    for _, w in ipairs(walls) do
        add.create(
            scene,
            w[1],
            w[2],
            w[3],
            { color = { 0.22, 0.32, 0.44, 1 } },
            { type = 'Static', friction = 0.7 }
        )
    end
    self.board = scene.world:create('BillboardUI', {
        name = 'CollisionControls',
        position = { -130, 55, -40 },
        size = { 0, 100, 0, 88 },
        sizeMode = 'World3D',
        canvasSize = { 0, 310, 0, 270 },
        onTop = false,
        maxDistance = 420,
    })
    return self
end

function Demo:spawn()
    if #self.items >= self.limit then
        self.running = false
        return
    end
    self.serial = self.serial + 1
    local kind = ({ 'cube', 'sphere', 'capsule' })[(self.serial - 1) % 3 + 1]
    local collider = kind == 'sphere' and { shape = 'Sphere', radius = 6 }
        or kind == 'capsule' and { height = 12, shape = 'Capsule', radius = 6 }
        or { shape = 'Box' }
    local mesh = add.create(
        self.scene,
        'Dropped' .. self.serial,
        {
            math.sin(self.serial * 2.3) * 38,
            105 + (self.serial % 3) * 14,
            50 + math.cos(self.serial * 1.7) * 38,
        },
        { 12, 12, 12 },
        { kind = kind, color = { 0.3 + (self.serial % 3) * 0.2, 0.65, 0.9, 1 } },
        { collider = collider, friction = 0.55, restitution = 0.15 }
    )
    self.items[#self.items + 1] = mesh
end

function Demo:reset()
    self.running = false
    self.elapsed = 0
    for i = #self.items, 1, -1 do
        self.items[i]:destroy()
        self.items[i] = nil
    end
end

function Demo:update(dt)
    self.elapsed = self.elapsed + dt
    if self.running and self.elapsed >= 0.2 then
        self.elapsed = self.elapsed % 0.2
        self:spawn()
    end
    self.scene.world:updateNodes(dt)
    self.scene.physics:update(dt)
    self.count.text = string.format(
        'Bodies: %d | dropped: %d/%d',
        #self.scene.physics.bodies,
        #self.items,
        self.limit
    )
end

return Demo
