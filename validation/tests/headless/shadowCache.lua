-- CPU/integration tests using an instrumented graphics API. No GPU rasterization.
unpack = unpack or table.unpack
package.preload.bit = package.preload.bit
    or function()
        return {
            band = function(...)
                local result = -1
                for _, v in ipairs({ ... }) do
                    result = bit32.band(result, v)
                end
                return result
            end,
        }
    end
local passes, uploads, clock, scissor, cleared = 0, 0, 1, nil, {}
local preparedCasters

local function resource()
    return {
        release = function() end,
        setFilter = function() end,
        setWrap = function() end,
        setDepthSampleMode = function() end,
        send = function() end,
        replacePixels = function()
            uploads = uploads + 1
        end,
        setPixel = function() end,
    }
end
katsa = {
    timer = {
        getTime = function()
            return clock
        end,
    },
    image = { newImageData = resource },
    graphics = {
        newShader = resource,
        newImage = resource,
        newCanvas = resource,
        getSystemLimits = function()
            return { texturesize = 4096 }
        end,
        getCanvasFormats = function()
            return { depth24 = true }
        end,
        push = function() end,
        pop = function() end,
        origin = function() end,
        setCanvas = function() end,
        setDepthMode = function() end,
        setFrontFaceWinding = function() end,
        setColor = function() end,
        setScissor = function(x, y, w, h)
            scissor = x and { x, y, w, h } or nil
        end,
        clear = function(color, stencil, depth)
            assert(color == false and stencil == false and depth == 1, 'Depth-only clear')
            assert(scissor, 'Cached atlas must never be cleared without a tile scissor')
            passes = passes + 1
            cleared[scissor[1] .. ':' .. scissor[2]] = true
        end,
    },
}
package.loaded['source.engine.graphics.pipeline.batches'] = {
    new = function()
        return {
            prepare = function(_, list)
                preparedCasters = {}
                for _, caster in ipairs(list) do
                    preparedCasters[#preparedCasters + 1] = caster
                end
            end,
            draw = function() end,
            release = function() end,
        }
    end,
}
local Shadows = require('source.engine.graphics.shadows.shadows')
local Math = require('source.engine.math.math3d')

local shadows = Shadows.new({
    own = function(_, v)
        return v
    end,
})
local count = 0

local function check(ok, msg)
    assert(ok, msg)
    count = count + 1
    print('PASS ' .. msg)
end
local settings = {
    enabled = true,
    resolution = 64,
    distance = 1000,
    near = 0.5,
    updateHz = 30,
    bias = 0.02,
    normalBias = 0.1,
    strength = 1,
    filterSamples = 1,
    layers = -1,
}
local world = {
    objects = {},
    lighting = {
        shadows = settings,
        sun = {
            enabled = false,
            direction = { 0, -1, 0 },
        },
    },
}
local camera = { position = { 0, 0, 0 } }
local first = {
    enabled = true,
    castShadow = true,
    type = 'PointLight3D',
    slot = 1,
    range = 40,
    radius = 20,
    worldPosition = { 0, 0, 0 },
    worldDirection = { 0, 0, 1 },
}
local second = {
    enabled = true,
    castShadow = true,
    type = 'SpotLight3D',
    slot = 2,
    range = 40,
    radius = 20,
    worldPosition = { 300, 0, 0 },
    worldDirection = { 0, 0, 1 },
}
local lights = { selected = { first, second } }
local object = {
    matrix = Math.identity(),
    worldPosition = { 0, 0, 10 },
    radius = 2,
    geometry = {},
    image = {},
    transparency = 0,
    color = { 1, 1, 1, 1 },
    isVisible = function(self)
        return self.visible ~= false
    end,
}
world.objects[1] = object

local function step()
    clock = clock + 0.1
    shadows:update(world, camera, lights, clock)
    return shadows.updatedFaces
end
check(step() == 7, 'First frame builds all local faces')
local generation, initialUploads = shadows.generation, uploads
check(step() == 0 and shadows.drawCalls == 0, 'Static scene does not redraw any depth face')
check(
    shadows.generation == generation and uploads == initialUploads,
    'Static scene reuses matrix texture and atlas generation'
)
camera.position[1] = 12
check(step() == 0, 'Camera3D motion leaves local maps cached')
cleared = {}
object.matrix[4] = 2
object.worldPosition[1] = 2
check(step() == 6 and shadows.updatedLights == 1, 'Movement updates only overlapping PointLight3D')
local untouchedTile = shadows.assignments[2].base
local tileKey = (untouchedTile % shadows.columns * shadows.resolution)
    .. ':'
    .. (math.floor(untouchedTile / shadows.columns) * shadows.resolution)
check(not cleared[tileKey], 'Selective refresh preserves the unrelated spotlight tile')
object.matrix[4] = 300
object.worldPosition[1] = 300
check(step() == 7, 'Teleport updates sources in old and new bounds')
object.visible = false
check(step() == 1, 'Hiding removes the previous shadow in its source region')
check(step() == 0, 'Hidden stationary object causes no repeat work')
object.visible = true
check(step() == 1, 'Showing restores the local shadow')
world.objects = {}
check(step() == 1, 'Deleting a caster invalidates its old region')
check(next(shadows.cache.objects) == nil, 'Removed object tracking does not retain nodes')
world.objects = { object }
check(step() == 1, 'Adding a caster updates only its local source')
object.parent = {}
check(step() == 1, 'Reparenting invalidates the affected source')
object.geometry = {}
check(step() == 1, 'Geometry replacement invalidates the affected source')
object.image = {}
check(step() == 1, 'Alpha texture replacement invalidates the affected source')
object.color[4] = 0.5
check(step() == 1, 'Opacity change invalidates the affected source')
object.shadowRevision = 1
check(step() == 1, 'Explicit revision supports in-place mesh or texture updates')
first.worldPosition[1] = 5
check(step() == 6, 'Moving one light updates only its maps')
second.worldDirection[1] = 0.1
check(step() == 1, 'Rotating a spotlight updates only its map')
settings.bias = 0.04
settings.filterSamples = 9
settings.strength = 0.5
check(step() == 0, 'Sampling-only settings reuse depth maps')
settings.layers = 2
check(step() == 7, 'Caster layer-mask changes invalidate maps')
settings.layers = -1
step()
object.material = { uniforms = { shift = { 0, 0, 0 } } }
check(step() == 7, 'Arbitrary vertex material uses conservative invalidation')
object.material.uniforms.shift[1] = 4
check(step() == 7, 'In-place material uniform changes invalidate maps')
check(step() == 0, 'Static custom material is cached')
object.material.animated = true
check(step() == 7 and step() == 7, 'Animated material refreshes at the configured frequency')
object.material = nil
step()
settings.enabled = false
step()
settings.enabled = true
check(step() == 7, 'Re-enabling shadows rebuilds the atlas contents')
world.lighting.sun.enabled = true
check(step() == 3, 'Enabling sun builds only its cascades')
check(step() == 0, 'Static sun and camera reuse all cascades')
camera.position[1] = 100
check(step() == 3, 'Camera3D translation updates sun without redrawing local maps')
settings.resolution = 128
check(step() == 10, 'Resizing the atlas rebuilds all active faces')
lights.selected = { second, first }
check(step() == 0, 'Selected permutation preserves resident maps without relocation')
shadows.nextUpdate = 0
check(step() == 10, 'Legacy forced refresh remains available')
local before = passes
clock = clock + 0.001
object.matrix[4] = 301
object.worldPosition[1] = 301
shadows:update(world, camera, lights, clock)
check(passes == before, 'Update frequency bounds repeated depth work')
check(step() == 4, 'Delayed changes are detected on the next eligible update')
-- Distance eligibility and uniforms must stay correct on throttled frames.
world.lighting.sun.enabled = false
world.objects = {}
settings.distance = 100
camera.position = { 0, 0, 0 }
lights.selected = { second }
settings.updateHz = 30
step()
check(
    shadows.updatedFaces == 0 and shadows.lightData[second.slot][1] == -1,
    'Distant source outside shadow-distance sphere skips map construction'
)
clock = clock + 0.001
shadows:update(world, camera, lights, clock)
check(shadows.lightData[second.slot][1] == -1, 'Throttled frame keeps distant map disabled')
camera.position = { 300, 0, 0 }
step()
check(
    shadows.updatedFaces == 1 and shadows.lightData[second.slot][1] >= 0,
    'Entering shadow distance builds and enables a previously deferred map'
)
camera.position = { 0, 0, 0 }
clock = clock + 0.001
shadows:update(world, camera, lights, clock)
check(
    shadows.updatedFaces == 0 and shadows.lightData[second.slot][1] == -1,
    'Leaving shadow distance disables sampling immediately without atlas relocation'
)
-- Configuration generations are complete; normal dirtiness drains each frame.
settings.distance = 1000
settings.maxUpdateFaces = 4
lights.selected = {}
for i = 1, 16 do
    lights.selected[i] = {
        enabled = true,
        castShadow = true,
        type = 'SpotLight3D',
        slot = i,
        range = 40,
        radius = 20,
        worldPosition = { 0, 0, 0 },
        worldDirection = { 0, 0, 1 },
    }
end
check(
    step() == 4 and shadows.pendingFaces == 12,
    'Initial atlas generation respects the face budget'
)
local valid = 0
for _, light in ipairs(lights.selected) do
    if shadows.lightData[light.slot][1] >= 0 then
        valid = valid + 1
    end
end
check(valid == 4, 'Only completed coherent source tiles are enabled for sampling')
for i = 1, 3 do
    clock = clock + 0.001
    shadows:update(world, camera, lights, clock)
end
check(shadows.pendingFaces == 0, 'Initial atlas queue drains without exceeding ordinary budget')
settings.updateHz = 1
for _, light in ipairs(lights.selected) do
    light.shadowRevision = 1
end
shadows.nextUpdate = -1
check(step() == 4 and shadows.pendingFaces == 12, 'Ordinary source changes respect the face budget')
clock = clock + 0.001
shadows:update(world, camera, lights, clock)
check(
    shadows.updatedFaces == 4 and shadows.pendingFaces == 8,
    'Pending work drains on render frames even at 1 Hz'
)
clock = clock + 0.001
shadows:update(world, camera, lights, clock)
clock = clock + 0.001
shadows:update(world, camera, lights, clock)
check(shadows.pendingFaces == 0, 'Low-Hz queue completes without waiting several seconds')
check(step() == 0, 'Completed maps return to static caching')
settings.resolution = 64
check(step() == 4 and shadows.pendingFaces == 12, 'Atlas resize respects the face budget')
for i = 1, 3 do
    clock = clock + 0.001
    shadows:update(world, camera, lights, clock)
end
-- The deprecated realtime flag has no priority or bypass behavior.
lights.selected = { first, second }
settings.maxUpdateFaces = 12
settings.updateHz = 30
camera.position = { 0, 0, 0 }
object.worldPosition = { 0, 0, 10 }
object.matrix[4] = 0
object.matrix[12] = 10
object.layers = 2
object.visible = true
object.shadowRealtime = true
object.material = nil
first.shadowLayers = 1
second.shadowLayers = -1
world.objects = { object }
step()
clock = clock + 0.001
object.matrix[4] = 1
object.worldPosition[1] = 1
shadows:update(world, camera, lights, clock)
check(shadows.updatedFaces == 0, 'All casters obey the same scan cadence without priority')
check(step() == 0, 'Layer-excluded caster does not rebuild unrelated sources')
first.shadowLayers = -1
step()
clock = clock + 0.001
object.matrix[4] = 2
object.worldPosition[1] = 2
shadows:update(world, camera, lights, clock)
check(shadows.updatedFaces == 0, 'Legacy shadowRealtime flag cannot bypass the shared cadence')
check(step() == 6, 'Eligible movement updates overlapping sources on the common cadence')
check(step() == 0, 'Unchanged caster still reuses cached maps')
check(shadows.lightData[first.slot][1] >= 0, 'Cache-hit frame retains valid local map uniforms')
clock = clock + 0.001
first.worldPosition[1] = 1
shadows:update(world, camera, lights, clock)
check(shadows.updatedFaces == 0, 'Moving lights obey the same scan cadence as casters')
check(step() == 6, 'Light movement updates its maps at the next common deadline')
camera = {
    position = { 0, 0, 0 },
    right = { 1, 0, 0 },
    up = { 0, 1, 0 },
    forward = { 0, 0, 1 },
    focal = 1000,
    width = 100,
    height = 100,
    near = 1,
    far = 100,
}
first.worldPosition = { 0, 0, 0 }
lights.selected = { first }
settings.visibleFacesOnly = true
check(
    step() == 1 and shadows.skippedFaces == 5,
    'Narrow forward view builds only the overlapping PointLight3D face'
)
check(
    shadows.lightData[1][3] == 16,
    'Per-face validity mask exposes only the completed forward tile'
)
camera.forward = { 1, 0, 0 }
camera.right = { 0, 0, -1 }
clock = clock + 0.001
shadows:update(world, camera, lights, clock)
check(
    shadows.updatedFaces == 1 and shadows.lightData[1][3] == 17,
    'Camera3D turn builds a deferred face without waiting for scan Hz'
)
camera.forward = { 0, 0, 1 }
camera.right = { 1, 0, 0 }
check(step() == 0, 'Returning to an unchanged completed face reuses its tile')
object.matrix[4] = 3
object.worldPosition[1] = 3
step()
check(
    preparedCasters and preparedCasters[1] == object,
    'Off-screen blockers remain eligible to shadow visible receivers'
)
-- Membership changes must never relocate/disable surviving maps.
local stable = Shadows.new({
    own = function(_, v)
        return v
    end,
})
settings.visibleFacesOnly = false
settings.maxUpdateFaces = 6
settings.updateHz = 30
world.lighting.sun.enabled = false
world.objects = {}
camera = { position = { 0, 0, 0 } }

local function source(kind, slot, x)
    return {
        enabled = true,
        castShadow = true,
        type = kind,
        slot = slot,
        range = 50,
        radius = 20,
        worldPosition = { x, 0, 0 },
        worldDirection = { 0, 0, 1 },
    }
end
local a, b, c, d =
    source('PointLight3D', 1, 0),
    source('SpotLight3D', 2, 0),
    source('PointLight3D', 3, 0),
    source('PointLight3D', 3, 0)
local selected = { limit = 3, selected = { a, b, c } }
for i = 1, 4 do
    clock = clock + 0.1
    stable:update(world, camera, selected, clock)
end
local bases, allocations = {}, stable.atlasAllocations
for _, r in ipairs(stable.assignments) do
    bases[r.light] = r.base
end
selected.selected = { b, c, d }
b.slot = 1
c.slot = 2
d.slot = 3
clock = clock + 0.1
stable:update(world, camera, selected, clock)
check(stable.atlasAllocations == allocations, 'Changing membership does not reallocate the atlas')
check(
    stable.lightData[b.slot][1] == bases[b] and stable.lightData[c.slot][1] == bases[c],
    'Surviving source bases and valid maps survive replacement'
)
check(
    stable.updatedFaces == 6 and stable.pendingFaces == 0,
    'Only the new PointLight3D is generated within the source budget'
)
check(stable.lightData[d.slot][3] == 63, 'New PointLight3D publishes all six faces coherently')
check(
    stable.assignments[3].light == d and stable.assignments[3].base == bases[a],
    'Reused tiles are assigned exclusively to their new owner'
)
c.shadowRevision = 1
d.shadowRevision = 1
clock = clock + 0.1
stable:update(world, camera, selected, clock)
check(
    stable.pendingFaces == 6 and stable.lightData[d.slot][3] == 63,
    'Queued refresh preserves the previously published coherent source'
)
d.destroyed = true
selected.selected = { b, c }
clock = clock + 0.001
stable:update(world, camera, selected, clock)
local retained = false
for _, r in pairs(stable.residents) do
    retained = retained or r.light == d
end
check(
    not retained and stable.pendingFaces == 0,
    'Destroyed source leaves residency and update queue'
)
stable:release()
shadows:release()
print(
    'PASSED ' .. count .. ' shadow cache assertions; graphics calls instrumented, no rasterization'
)
