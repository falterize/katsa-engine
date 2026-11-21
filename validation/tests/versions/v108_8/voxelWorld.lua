-- voxelWorld scene: visible-face meshing, terrain, ray traversal, walker collision and a scene run
-- with real Actor workers (generate, mesh, spawn, break a block).
local Application = require('source.runtime.application')
local Raycast = require('game.scenes.voxelWorld.scripts.world.raycast')
local Walker = require('game.scenes.voxelWorld.scripts.player.walker')

local Module = {}
local ROOT = 'game/scenes/voxelWorld/assets/worker/'

local function load(name)
    package.loaded[name] = nil
    package.preload[name] = nil
    local chunk = assert(loadfile(ROOT .. name .. '.lua'))
    package.loaded[name] = chunk()
    return package.loaded[name]
end

-- A flat test world: solid below y = 5, optional wall at x >= 3.
local function fakeWorld(wall)
    return {
        blocks = { HEIGHT = 64 },
        getBlock = function(_, x, y)
            return (y < 5 or (wall and x >= 3 and y < 9)) and 1 or 0
        end,
        isSolid = function(self, x, y, z)
            return self:getBlock(x, y, z) ~= 0
        end,
    }
end

function Module.run(self)
    local Blocks = load('blocks')
    local Terrain = load('terrain')
    local Mesher = load('mesher')
    local size = Blocks.CHUNK * Blocks.CHUNK * Blocks.HEIGHT
    local function chunkWith(cells)
        local data = {}
        for i = 1, size do
            data[i] = '\0'
        end
        for _, c in ipairs(cells) do
            data[c[1] + c[3] * 16 + c[2] * 256 + 1] = string.char(c[4] or 3)
        end
        return table.concat(data)
    end
    local _, one = Mesher.build(chunkWith({ { 5, 5, 5 } }), {})
    local _, two = Mesher.build(chunkWith({ { 5, 5, 5 }, { 6, 5, 5 } }), {})
    self:check(one == 6 and two == 6, 'Only faces next to air are meshed and equal neighbours merge (1 block: 6 faces, 2 touching blocks: still 6 rectangles)')
    local _, hidden = Mesher.build(chunkWith({ { 0, 5, 5 } }), { nx = chunkWith({ { 15, 5, 5 } }) })
    self:check(hidden == 5, 'A face against a solid block of the neighbouring chunk is not drawn')

    local a, b = Terrain.generate(2, -3, 1337), Terrain.generate(2, -3, 1337)
    self:check(a == b and #a == size and a ~= Terrain.generate(3, -3, 1337), 'Terrain is deterministic and differs per chunk')

    local world = fakeWorld(false)
    local hit = Raycast.cast(setmetatable({ getBlock = world.getBlock }, { __index = world }), 0.5, 8.5, 0.5, 0, -1, 0, 6)
    self:check(hit and hit.y == 4 and hit.py == 5, 'A ray down hits the top block and names the empty block above it')

    local walker = Walker.new(fakeWorld(true), { walkSpeed = 4.3, sprintSpeed = 6, flySpeed = 10, flySprintSpeed = 20, jumpSpeed = 9, gravity = 32 })
    walker:teleport(0.5, 9, 0.5)
    for _ = 1, 90 do
        walker.forward, walker.yaw = 1, 90 -- yaw 90 walks along +X into the wall
        walker:update(1 / 60)
    end
    self:check(walker.onGround and math.abs(walker.y - 5) < 0.01, 'The walker falls and stands on the ground')
    self:check(walker.x < 3 - 0.29 and walker.x > 2, 'The walker stops at a wall instead of passing through')

    local scene = Application.new(self.manager, 'voxelWorld')
    scene:load()
    local state = scene.demo
    local frames = 0
    while frames < 900 and not state.spawned do
        scene:update(1 / 60, 1 / 60)
        scene:draw()
        katsa.timer.sleep(0.004)
        frames = frames + 1
    end
    self:check(state.spawned and state.voxels.stats.faces > 0, 'The world generates and meshes on Actor workers, then the player spawns')
    local voxels = state.voxels
    local x, z = math.floor(state.walker.x), math.floor(state.walker.z)
    local y = voxels:surface(x, z)
    self:check(voxels:setBlock(x, y, z, 0) and voxels:getBlock(x, y, z) == 0, 'A block can be broken')
    self:check(voxels:setBlock(x, y, z, 7) and voxels:getBlock(x, y, z) == 7, 'A block can be placed')
end

return Module
