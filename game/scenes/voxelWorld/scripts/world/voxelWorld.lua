-- The block world: chunk storage, streaming around the player and the chunk mesh nodes.
-- Terrain generation and meshing run on an Actor (worker threads); this module only copies the
-- results in, uploads finished meshes within a per-frame budget and answers block queries.
local ffi = require('ffi')
local Geometry = require('source.engine.graphics.geometry.primitives')
local Mesh = require('source.engine.composition.mesh')

local VoxelWorld = {}
VoxelWorld.__index = VoxelWorld

function VoxelWorld.new(scene, context, blocks, settings)
    local self = setmetatable({
        scene = scene,
        blocks = blocks,
        settings = settings,
        chunks = {},
        saved = {}, -- edited chunks that were unloaded, so edits survive walking away
        pending = {}, -- finished meshes waiting for upload
        generating = 0,
        meshing = 0,
        centre = nil,
        order = {},
        size = blocks.CHUNK * blocks.CHUNK * blocks.HEIGHT,
        stats = { chunks = 0, faces = 0, meshes = 0 },
    }, VoxelWorld)
    local world = scene.world
    -- The block shader (occlusion shade, tile repeat) applies to every chunk mesh below it.
    self.group = world:create('Shader3D', {
        name = 'Chunks',
        shaderPath = 'scene://shaders/voxel.glsl',
    })
    local root = 'scene://worker/'
    self.actor = world:create('Actor', {
        name = 'ChunkBuilder',
        script = root .. 'chunkBuilder.lua',
        workers = 2,
        modules = {
            blocks = root .. 'blocks.lua',
            terrain = root .. 'terrain.lua',
            mesher = root .. 'mesher.lua',
        },
    })
    return self
end

local function key(cx, cz)
    return (cx + 32768) * 65536 + (cz + 32768)
end

function VoxelWorld:chunkAt(cx, cz)
    return self.chunks[key(cx, cz)]
end

-- Block id at world coordinates; nil while the chunk is not loaded.
function VoxelWorld:getBlock(x, y, z)
    if y < 0 then
        return 1
    elseif y >= self.blocks.HEIGHT then
        return 0
    end
    local size = self.blocks.CHUNK
    local cx, cz = math.floor(x / size), math.floor(z / size)
    local chunk = self.chunks[key(cx, cz)]
    if not chunk or not chunk.ready then
        return nil
    end
    return chunk.data[(x - cx * size) + (z - cz * size) * size + y * size * size]
end

function VoxelWorld:isSolid(x, y, z)
    local id = self:getBlock(x, y, z)
    return id == nil or id ~= 0
end

local function markDirty(self, cx, cz)
    local chunk = self.chunks[key(cx, cz)]
    if chunk then
        chunk.dirty = true
    end
end

function VoxelWorld:setBlock(x, y, z, id)
    local size = self.blocks.CHUNK
    if y < 0 or y >= self.blocks.HEIGHT then
        return false
    end
    local cx, cz = math.floor(x / size), math.floor(z / size)
    local chunk = self.chunks[key(cx, cz)]
    if not chunk or not chunk.ready then
        return false
    end
    local lx, lz = x - cx * size, z - cz * size
    chunk.data[lx + lz * size + y * size * size] = id
    chunk.modified, chunk.dirty = true, true
    -- A block on the border changes which faces the neighbouring chunk has to draw.
    if lx == 0 then
        markDirty(self, cx - 1, cz)
    elseif lx == size - 1 then
        markDirty(self, cx + 1, cz)
    end
    if lz == 0 then
        markDirty(self, cx, cz - 1)
    elseif lz == size - 1 then
        markDirty(self, cx, cz + 1)
    end
    return true
end

-- Highest solid block of a column in a loaded chunk, or nil.
function VoxelWorld:surface(x, z)
    for y = self.blocks.HEIGHT - 1, 0, -1 do
        local id = self:getBlock(x, y, z)
        if id == nil then
            return nil
        elseif id ~= 0 then
            return y
        end
    end
    return 0
end

function VoxelWorld:requestChunk(cx, cz)
    local k = key(cx, cz)
    local chunk = { cx = cx, cz = cz, key = k }
    self.chunks[k] = chunk
    local saved = self.saved[k]
    if saved then
        self.saved[k] = nil
        chunk.data, chunk.ready, chunk.modified = saved, true, true
        return
    end
    self.generating = self.generating + 1
    self.actor:request('generate', { cx = cx, cz = cz, seed = self.settings.seed }, function(ok, data)
        self.generating = self.generating - 1
        if not ok then
            error('Chunk generation failed: ' .. tostring(data))
        end
        if self.chunks[k] ~= chunk then
            return -- unloaded while the worker was busy
        end
        chunk.data = ffi.new('uint8_t[?]', self.size)
        ffi.copy(chunk.data, data, self.size)
        chunk.ready = true
    end)
end

local function snapshot(self, chunk)
    return ffi.string(chunk.data, self.size)
end

local DIRECTIONS = {
    { 'px', 1, 0 },
    { 'nx', -1, 0 },
    { 'pz', 0, 1 },
    { 'nz', 0, -1 },
}

-- Meshing needs the four neighbours so border faces are decided correctly.
local function meshRequest(self, chunk)
    local request = { blocks = snapshot(self, chunk) }
    for _, d in ipairs(DIRECTIONS) do
        local other = self.chunks[key(chunk.cx + d[2], chunk.cz + d[3])]
        if not (other and other.ready) then
            return nil
        end
        request[d[1]] = snapshot(self, other)
    end
    return request
end

function VoxelWorld:requestMesh(chunk)
    local request = meshRequest(self, chunk)
    if not request then
        return false
    end
    -- `seq` numbers the request: only the newest answer is uploaded, older ones are dropped.
    chunk.seq = (chunk.seq or 0) + 1
    local seq = chunk.seq
    chunk.dirty, chunk.meshing, chunk.queued = false, true, true
    self.meshing = self.meshing + 1
    self.actor:request('mesh', request, function(ok, result)
        self.meshing = self.meshing - 1
        chunk.meshing = false
        if not ok then
            error('Chunk meshing failed: ' .. tostring(result))
        end
        if self.chunks[chunk.key] == chunk then
            self.pending[#self.pending + 1] = { chunk = chunk, result = result, seq = seq }
        end
    end)
    return true
end

local function destroyNodes(chunk)
    for _, node in pairs(chunk.nodes or {}) do
        node:destroy()
    end
    chunk.nodes = nil
end

local function upload(self, entry)
    local chunk, result = entry.chunk, entry.result
    if self.chunks[chunk.key] ~= chunk then
        return
    end
    if entry.seq ~= chunk.seq then
        return -- a newer mesh was requested meanwhile
    end
    chunk.queued = false
    local size = self.blocks.CHUNK
    local section = self.blocks.SECTION
    chunk.version = (chunk.version or 0) + 1
    local nodes = {}
    for _, part in ipairs(result.sections) do
        local flat, count = part.vertices, #part.vertices / 8
        local vertices = {}
        for i = 1, count do
            local at = (i - 1) * 8
            vertices[i] = {
                flat[at + 1], flat[at + 2], flat[at + 3], flat[at + 4],
                flat[at + 5], flat[at + 6], flat[at + 7], flat[at + 8],
            }
        end
        -- Node names are unique and the old meshes stay until the new ones exist (no flicker).
        nodes[part.sy] = Mesh.create(self.scene.world, {
            name = ('Chunk %d,%d,%d v%d'):format(chunk.cx, chunk.cz, part.sy, chunk.version),
            geometry = Geometry.mesh(vertices),
            position = {
                chunk.cx * size + size / 2,
                part.sy * section + section / 2,
                chunk.cz * size + size / 2,
            },
            surfaceAppearance = { colorMap = 'blocks', pixelate = true },
        }, self.group)
    end
    self.stats.faces = self.stats.faces - (chunk.faces or 0) + result.faces
    chunk.faces = result.faces
    destroyNodes(chunk)
    chunk.nodes, chunk.meshed = nodes, true
    self.stats.meshes = self.stats.meshes + 1
end

local function unload(self, chunk)
    if chunk.modified and chunk.ready then
        self.saved[chunk.key] = chunk.data
    end
    destroyNodes(chunk)
    self.stats.faces = self.stats.faces - (chunk.faces or 0)
    self.chunks[chunk.key] = nil
end

-- The chunks to keep, nearest first: a disc of viewDistance + 1 (the outer ring is only
-- generated, so the meshed ring always has all four neighbours).
local function rescan(self, pcx, pcz)
    local radius = self.settings.viewDistance + 1
    local order = {}
    for dz = -radius, radius do
        for dx = -radius, radius do
            local d2 = dx * dx + dz * dz
            if d2 <= radius * radius + 1 then
                order[#order + 1] = { cx = pcx + dx, cz = pcz + dz, d2 = d2 }
            end
        end
    end
    table.sort(order, function(a, b)
        return a.d2 < b.d2
    end)
    self.order, self.centre = order, { pcx, pcz }
    local keep = (radius + 1) ^ 2 + 2
    for _, chunk in pairs(self.chunks) do
        local dx, dz = chunk.cx - pcx, chunk.cz - pcz
        if dx * dx + dz * dz > keep and not chunk.meshing then
            unload(self, chunk)
        end
    end
end

function VoxelWorld:update(px, pz)
    local size = self.blocks.CHUNK
    local pcx, pcz = math.floor(px / size), math.floor(pz / size)
    if not self.centre or self.centre[1] ~= pcx or self.centre[2] ~= pcz then
        rescan(self, pcx, pcz)
    end
    local settings = self.settings
    local viewSquared = settings.viewDistance ^ 2 + 1
    local loaded = 0
    for _, entry in ipairs(self.order) do
        local chunk = self.chunks[key(entry.cx, entry.cz)]
        if not chunk then
            if self.generating < settings.maxGenerating then
                self:requestChunk(entry.cx, entry.cz)
            end
        elseif
            chunk.ready
            and (chunk.dirty or not chunk.meshed)
            and not chunk.meshing
            and not chunk.queued
            and entry.d2 <= viewSquared
            and self.meshing < settings.maxMeshing
        then
            self:requestMesh(chunk)
        end
        if chunk and chunk.ready then
            loaded = loaded + 1
        end
    end
    self.stats.chunks = loaded
    for _ = 1, settings.meshesPerFrame do
        local entry = table.remove(self.pending, 1)
        if not entry then
            break
        end
        upload(self, entry)
    end
end

-- True once the chunk around (x, z) is drawn, so the player can safely start there.
function VoxelWorld:isReady(x, z)
    local size = self.blocks.CHUNK
    local chunk = self:chunkAt(math.floor(x / size), math.floor(z / size))
    return chunk ~= nil and chunk.ready and chunk.meshed == true
end

function VoxelWorld:release()
    self.pending = {}
    if self.actor and not self.actor.destroyed then
        self.actor:destroy()
    end
end

return VoxelWorld
