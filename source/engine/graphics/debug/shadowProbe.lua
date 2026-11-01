-- Opt-in whole-frame A/B probe with GPU completion through readback.
-- Deltas estimate incremental costs, not isolated GPU timer-query durations.
local Probe = {}

function Probe.measure(renderer, world, camera, time, repeats)
    repeats = repeats or 3
    assert(repeats >= 1 and repeats <= 20, 'Probe repeat limit is 1..20')
    renderer:draw(world, camera, time)
    local freeze, disabled = renderer.freezeShadowUpdates, renderer.shadows.samplingDisabled
    local frameCache = world.environment.render.frameCache
    world.environment.render.frameCache = false
    local samples, buildCPU = {}, 0
    local ok, err = pcall(function()
        for mode = 1, 3 do
            renderer.freezeShadowUpdates = mode ~= 3
            renderer.shadows.samplingDisabled = mode ~= 2

            local function render()
                if mode == 3 then
                    renderer.shadows.nextUpdate = 0
                end
                renderer:draw(world, camera, time)
                local data = renderer.canvas:newImageData()
                data:release()
            end
            render() -- Shader compilation/initial allocation outside samples.
            local start = katsa.timer.getTime()
            for i = 1, repeats do
                render()
                if mode == 3 then
                    buildCPU = buildCPU + renderer.stats.shadowBuildMilliseconds
                end
            end
            samples[mode] = (katsa.timer.getTime() - start) * 1000 / repeats
        end
    end)
    renderer.freezeShadowUpdates, renderer.shadows.samplingDisabled = freeze, disabled
    world.environment.render.frameCache = frameCache
    if not ok then
        error(err, 0)
    end
    renderer.stats.shadowSamplingProbeMilliseconds = samples[2] - samples[1]
    renderer.stats.shadowBuildProbeMilliseconds = samples[3] - samples[1]
    return {
        withoutSampling = samples[1],
        withSampling = samples[2],
        difference = samples[2] - samples[1],
        withRebuild = samples[3],
        buildDifference = samples[3] - samples[1],
        buildCPUMilliseconds = buildCPU / repeats,
        includesReadback = true,
    }
end

return Probe
