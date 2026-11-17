-- Voxel world scene: a chunked block world (terrain and meshes built by Actor workers) with a
-- creative-mode player: walk, jump, fly, break and place blocks, nine-slot hotbar.
local Blocks = require('../assets.worker.blocks')
local Hotbar = require('./player.hotbar')
local Input = require('./player.input')
local Interaction = require('./player.interaction')
local Walker = require('./player.walker')
local VoxelWorld = require('./world.voxelWorld')

local Content = {}
Content.__index = Content

function Content.new(scene)
    local settings = scene.settings
    local world = scene.world
    local environment = world.environment
    environment.debug.gizmos.enabled = false
    environment.shadows.enabled = false
    environment.ambient = { 120, 128, 150 }
    environment.sky.enabled = true
    local view = settings.world.viewDistance * Blocks.CHUNK
    environment.fog.enabled = true
    environment.fog.offset = view * 0.55
    environment.fog.maxOpacity = 1
    world:create('DirectionalLight3D', {
        name = 'Sun',
        rotation = { 50, 35, 0 },
        color = { 255, 244, 222 },
        brightness = 1.15,
    })

    local self = setmetatable({ scene = scene, blocks = Blocks, settings = settings }, Content)
    self.voxels = VoxelWorld.new(scene, scene.context or scene, Blocks, settings.world)
    self.walker = Walker.new(self.voxels, settings.player)
    self.hotbar = Hotbar.new(Blocks)
    local camera = scene.camera
    camera.near, camera.far, camera.fov = 0.05, view * 2 + 64, settings.player.fov
    camera.drawDistance = view * 2 + 64
    camera.position = { 0, 80, 0 }
    camera.rotation = { -15, 0, 0 }
    self.interaction = Interaction.new(scene, self.voxels, self.walker, self.hotbar, camera, settings.player)
    scene.input = Input.new(scene, self)
    self.look = function(dx, dy)
        camera:look(dx, dy, settings.player.sensitivity)
        camera.rotation[1] = math.max(-89, math.min(89, camera.rotation[1]))
    end
    self.spawned = false
    return self
end

-- Waits for the first chunk, then drops the player onto the surface of the spawn column.
function Content:spawn()
    local voxels = self.voxels
    if not voxels:isReady(0.5, 0.5) then
        return false
    end
    local ground = voxels:surface(0, 0)
    self.walker:teleport(0.5, ground + 1, 0.5)
    self.spawned = true
    return true
end

function Content:update(dt)
    local scene, walker, voxels = self.scene, self.walker, self.voxels
    -- Node updates deliver the Actor's answers, so they run even before the player spawns.
    scene.world:updateNodes(dt)
    voxels:update(walker.x, walker.z)
    if not self.spawned and not self:spawn() then
        self:updateStatus()
        return
    end
    local camera = scene.camera
    walker.yaw = camera.rotation[2]
    walker:update(dt)
    camera.position = { walker.x, walker.y + self.settings.player.eyeHeight, walker.z }
    self.interaction:update()
    self:updateStatus()
end

function Content:updateStatus()
    local status, walker, stats = self.status, self.walker, self.voxels.stats
    if not status then
        return
    end
    local text = ('%s   XYZ %.1f %.1f %.1f\nChunks %d, faces %d (only visible ones), generating %d, meshing %d\nWASD move, Space jump (double tap or F: fly), Shift down, Ctrl sprint\nLMB break, RMB place, MMB pick, wheel/1-9 slot, E blocks, Tab menu'):format(
        walker.flying and 'Flying' or 'Walking',
        walker.x, walker.y, walker.z,
        stats.chunks, stats.faces, self.voxels.generating, self.voxels.meshing
    )
    if not self.spawned then
        text = 'Generating the world...'
    end
    if text ~= status.text then
        status.text = text
    end
end

function Content:release()
    self.voxels:release()
    self.interaction:release()
end

return Content
