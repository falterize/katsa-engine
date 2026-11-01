local Benchmark = {}
Benchmark.__index = Benchmark

function Benchmark.new(manager)
    love.window.setVSync(0)
    local scene = manager:switch(require('source.game.runtime.game').new, 'lights32')
    scene.world.lighting.fog.enabled = false
    return setmetatable({
        manager = manager,
        scene = scene,
        densities = { 1, 2 },
        case = 1,
        frames = 0,
        samples = 0,
        total = 0,
        results = {},
    }, Benchmark)
end

function Benchmark:update() end

function Benchmark:draw()
    self.frames = self.frames + 1
    if self.frames > 30 then
        love.graphics.flushBatch()
        -- Readback synchronizes the GPU; this is a render workload comparison, not device FPS.
        local start = love.timer.getTime()
        for i = 1, 3 do
            self.scene.renderer:draw(self.scene.world, self.scene.camera, self.scene.time)
        end
        local pixels = self.scene.renderer.canvas:newImageData()
        pixels:release()
        self.total = self.total + (love.timer.getTime() - start) / 3
        self.samples = self.samples + 1
    end
    if self.samples >= 20 then
        local renderer = self.scene.renderer
        local result = string.format(
            'Density %.2f | %dx%d pixels | %d active lights | synchronized render %.3f ms',
            renderer.renderDensity,
            renderer.canvas:getPixelWidth(),
            renderer.canvas:getPixelHeight(),
            renderer.stats.lights,
            self.total / self.samples * 1000
        )
        print(result)
        self.results[#self.results + 1] = result
        self.case = self.case + 1
        if self.case > #self.densities then
            local name, version, vendor, device = love.graphics.getRendererInfo()
            self.results[#self.results + 1] = table.concat({ name, version, vendor, device }, ' / ')
            love.filesystem.write('benchmarkReport.txt', table.concat(self.results, '\n'))
            love.event.quit(0)
        else
            renderer.renderDensity = self.densities[self.case]
            self.frames = 0
            self.samples = 0
            self.total = 0
        end
    end
end

return Benchmark
