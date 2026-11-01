-- Same scene and harness run against v85 and v86; no quality settings are reduced.
local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    love.errorhandler = function(message)
        print('FAILED profile ' .. tostring(message))
        os.exit(1)
    end
    for _, flag in ipairs(arg or {}) do
        if
            flag == '--profile-v89-interpreter'
            or flag == '--profile-v86-interpreter'
            or flag == '--profile-v87-interpreter'
            or flag == '--profile-v88-interpreter'
        then
            jit.off()
            jit.flush()
        end
    end
    love.window.setMode(810, 330, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    print('DEVICE', love.graphics.getRendererInfo())
    print('JIT', jit.status(), jit.arch)
    print('case,checks,meshes,lights,other,prepare,submit,complete,updated,reused')
    local referencePath = os.getenv('KATSA_REFERENCE_INSPECTOR')
    local reference
    if referencePath then
        print('PAIRED probes enabled; complete includes two extra inspections')
        local file = assert(io.open(referencePath, 'rb'))
        local source = file:read('*a')
        file:close()
        local chunk = assert(loadstring(source, 'reference.frameCache'))
        local snapshotPath = os.getenv('KATSA_REFERENCE_SNAPSHOT')
        if snapshotPath then
            local snapshotFile = assert(io.open(snapshotPath, 'rb'))
            local snapshotSource = snapshotFile:read('*a')
            snapshotFile:close()
            local snapshot = assert(loadstring(snapshotSource, 'reference.propertySnapshot'))()

            local function referenceRequire(name)
                if name == 'source.engine.graphics.pipeline.propertySnapshot' then
                    return snapshot
                end
                return require(name)
            end
            setfenv(chunk, setmetatable({ require = referenceRequire }, { __index = _G }))
        end
        reference = chunk()
    end
    local optimized = require('source.engine.graphics.pipeline.frameCache')
    for _, mode in ipairs({ 'Static', 'Cube', 'Camera' }) do
        local scene = self.manager:switch(require('source.game.runtime.game').new, 'combined')
        local w, r, c = scene.world, scene.renderer, scene.camera
        w.environment.shadows.enabled = false
        w.environment.debug.gizmos.enabled = false
        local cube = w.byName['Cube10.2']
        local base, yaw = c.position[1], c.rotation[2]
        local sums = {}
        local n = 0
        local referenceCache, optimizedCache
        local referenceSamples, optimizedSamples = {}, {}

        local function inspectBoth(frame, t)
            local drawingCache = r._frameCache

            local function sample(inspector, cache, samples)
                r._frameCache = cache
                local start = love.timer.getTime()
                local result = inspector.inspect(r, w, c, t, true)
                local elapsed = (love.timer.getTime() - start) * 1000
                if frame > 30 then
                    samples[#samples + 1] = elapsed
                end
                return result
            end
            if frame % 2 == 0 then
                referenceCache = sample(reference, referenceCache, referenceSamples)
                optimizedCache = sample(optimized, optimizedCache, optimizedSamples)
            else
                optimizedCache = sample(optimized, optimizedCache, optimizedSamples)
                referenceCache = sample(reference, referenceCache, referenceSamples)
            end
            r._frameCache = drawingCache
        end
        for frame = 1, 150 do
            local t = frame / 60
            local start = love.timer.getTime()
            scene:update(1 / 60, 1 / 60)
            if mode == 'Cube' then
                cube.position[2] = math.sin(t * 2) * 18
                cube.rotation[2] = t * 60
            end
            if mode == 'Camera' then
                c.position[1] = base + math.sin(t) * 30
                c.rotation[2] = yaw + math.sin(t) * 5
            end
            if reference then
                inspectBoth(frame, t)
            end
            r:draw(w, c, t, true)
            local data = r.canvas:newImageData()
            data:release()
            local complete = (love.timer.getTime() - start) * 1000
            if frame > 30 then
                local phases = r._frameCache.timings
                local values = {
                    checks = r.stats.cacheCheckMilliseconds,
                    meshes = phases.objects,
                    lights = phases.lights + phases.directionalLights,
                    other = phases.guards + phases.shaderNodes + phases.other,
                    prepare = r.stats.cullingMilliseconds,
                    submit = r.stats.mainSubmissionMilliseconds,
                    complete = complete,
                    updated = r.stats.updatedMeshes,
                    reused = r.stats.frameReused and 1 or 0,
                }
                for key, value in pairs(values) do
                    sums[key] = (sums[key] or 0) + value
                end
                n = n + 1
            end
        end
        local row = { mode }
        for _, key in ipairs({
            'checks',
            'meshes',
            'lights',
            'other',
            'prepare',
            'submit',
            'complete',
            'updated',
            'reused',
        }) do
            row[#row + 1] = string.format('%.4f', sums[key] / n)
        end
        print(table.concat(row, ','))
        print('SCALAR SCHEMAS', r._frameCache.scalarNodesSkipped, r._frameCache.scalarNodesChecked)
        if reference then
            local function summary(samples)
                table.sort(samples)
                local sum = 0
                for _, value in ipairs(samples) do
                    sum = sum + value
                end
                return sum / #samples,
                    samples[math.ceil(#samples * 0.5)],
                    samples[math.ceil(#samples * 0.9)]
            end
            local oldMean, oldMedian, oldP90 = summary(referenceSamples)
            local newMean, newMedian, newP90 = summary(optimizedSamples)
            print(
                string.format(
                    'PAIRED %s reference mean %.4f median %.4f p90 %.4f | optimized mean %.4f median %.4f p90 %.4f',
                    mode,
                    oldMean,
                    oldMedian,
                    oldP90,
                    newMean,
                    newMedian,
                    newP90
                )
            )
        end
    end
    print('PROFILE COMPLETE')
    love.event.quit()
end

return T
