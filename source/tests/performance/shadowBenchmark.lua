-- Identical static geometry/camera/quality for all cases. Readback synchronizes
-- software GL; this is renderer workload, not Android FPS or a GPU timer.
local Benchmark = {}
Benchmark.__index = Benchmark
local cases = {
    { 1, false, false },
    { 1, true, false },
    { 32, false, false },
    { 32, true, false },
    {
        32,
        true,
        true,
    },
}

function Benchmark.new(manager)
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    local Resources = require('source.engine.core.resources')
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.sun.enabled = false
    settings.fog.enabled = false
    settings.sky.enabled = false
    settings.gizmos.enabled = false
    settings.shadows.resolution = 256
    settings.shadows.filterSamples = 4
    settings.shadows.distance = 500
    settings.shadows.maxUpdateFaces = 12
    settings.shadows.visibleFacesOnly = true
    settings.lightSettings.cullInvisible = false
    local world = require('source.engine.world.world').new(resources, settings)
    local camera = world:addCamera({
        position = { 0, 100, -240 },
        rotation = { -12, 0, 0 },
        drawDistance = 1000,
    })
    world:create('Mesh3D', {
        name = 'Floor',
        kind = 'plane',
        position = { 0, -12, 120 },
        size = { 800, 0, 800 },
        texture = 'white',
        castShadow = false,
    })
    local caster
    for x = 1, 20 do
        for z = 1, 20 do
            local object = world:create('Mesh3D', {
                name = 'Cube' .. x .. '.' .. z,
                position = { (x - 10.5) * 24, 0, z * 24 - 60 },
                size = { 14, 18, 14 },
                texture = 'white',
            })
            if x == 10 and z == 8 then
                caster = object
            end
        end
    end
    for i = 1, 32 do
        world:create('PointLight3D', {
            name = 'Light' .. i,
            position = { ((i - 1) % 8 - 3.5) * 42, 40, math.floor((i - 1) / 8) * 60 },
            range = 150,
            radius = 25,
            brightness = 1.5,
            castShadow = true,
        })
    end
    local renderer = require('source.engine.graphics.pipeline.renderer').new(resources)
    renderer.renderDensity = 1
    renderer.msaa = 0
    local name, version, vendor, device = katsa.graphics.getRendererInfo()
    print('BENCHMARK ' .. table.concat({ name, version, vendor, device }, ' / '))
    return setmetatable({
        resources = resources,
        world = world,
        camera = camera,
        renderer = renderer,
        caster = caster,
        case = 1,
        frame = 0,
        total = 0,
        samples = 0,
        results = {},
        faces = 0,
        draws = 0,
        submitted = 0,
        tests = 0,
        peak = 0,
    }, Benchmark)
end

function Benchmark:update() end

function Benchmark:draw()
    local entry = cases[self.case]
    local r, w = self.renderer, self.world
    if self.frame == 0 then
        w.lighting.lightSettings.maxActiveLights = entry[1]
        w.lighting.shadows.enabled = entry[2]
        r.lights.nextSelection = 0
    end
    self.frame = self.frame + 1
    if entry[3] then
        self.caster.position[1] = self.frame % 2 == 0 and 4 or -4
        r.shadows.nextUpdate = -1
    end
    local start = katsa.timer.getTime()
    r:draw(w, self.camera, self.frame / 60)
    local pixels = r.canvas:newImageData()
    pixels:release()
    local elapsed = (katsa.timer.getTime() - start) * 1000
    if self.frame <= 30 then
        self.peak = math.max(self.peak, elapsed)
    else
        self.total = self.total + elapsed
        self.samples = self.samples + 1
        self.faces = self.faces + r.stats.shadowFaces
        self.draws = self.draws + r.stats.shadowDrawCalls
        self.submitted = self.submitted + (r.stats.shadowCasterSubmissions or 0)
        self.tests = self.tests + (r.stats.shadowCasterTests or 0)
    end
    if self.samples == 12 then
        local msg = string.format(
            '%d lights / shadows %s / %s / %.3f ms mean / %.3f ms warmup peak / faces %.1f / depth draws %.1f / caster submissions %.1f / caster tests %.1f / atlas %dx%d @ %d / allocations %d / filter %d / visible %d / pending %d',
            entry[1],
            entry[2] and 'ON' or 'OFF',
            entry[3] and 'DYNAMIC' or 'STATIC',
            self.total / self.samples,
            self.peak,
            self.faces / self.samples,
            self.draws / self.samples,
            self.submitted / self.samples,
            self.tests / self.samples,
            r.shadows.columns or 0,
            r.shadows.rows or 0,
            r.shadows.resolution or 0,
            r.shadows.atlasAllocations or 0,
            w.lighting.shadows.filterSamples,
            r.stats.objects,
            r.stats.shadowPendingFaces or 0
        )
        print(msg)
        self.results[#self.results + 1] = msg
        self.case = self.case + 1
        self.frame = 0
        self.total = 0
        self.samples = 0
        self.faces = 0
        self.draws = 0
        self.submitted = 0
        self.tests = 0
        self.peak = 0
        if self.case > #cases then
            katsa.filesystem.write('shadowBenchmark.txt', table.concat(self.results, '\n'))
            r:release()
            w:release()
            self.resources:release()
            print('BENCHMARK COMPLETE')
            katsa.event.quit()
        end
    end
end

return Benchmark
