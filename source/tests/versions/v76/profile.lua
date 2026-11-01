-- Shared v75/v76 workload. Readback wait is not a GPU timer.
local T = {}
T.__index = T

function T.new(manager)
    katsa.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    print('DEVICE', katsa.getVersion(), katsa.graphics.getRendererInfo())
    local modes = { 'Idle', 'Camera', 'Cube', 'Lights', 'All' }
    local output = os.getenv('KATSA_PROFILE_OUTPUT')
    for _, zone in ipairs({ 'combined', 'shadows' }) do
        local s = self.manager:switch(require('source.game.runtime.game').new, zone)
        local r, w, c = s.renderer, s.world, s.camera
        w.environment.gizmos.enabled = false
        s.showStats = false
        w.environment.shadows.sourceFadeSeconds = 0 -- Remove wall-clock fade from paired captures.
        -- The stress scene has both independent motion buttons; exercise their handlers.
        local motion = s.stressMotion
        local timer = require('source.tests.performance.gpuTimer').new()
        print('GPU_TIMER', timer and 'GL_TIME_ELAPSED (software driver)' or 'Unavailable')
        local oldPrepare, oldShadow, oldFace = r.prepare, r.shadows.update, r.shadows.drawFace
        local shadowComparisons, shadowRows = 0, 0
        r.shadows.drawFace = function(sh, ...)
            oldFace(sh, ...)
            shadowComparisons = shadowComparisons + sh.batches.comparisons
            shadowRows = shadowRows + sh.batches.matrixRows
        end
        r.shadows.update = function(sh, ...)
            shadowComparisons, shadowRows = 0, 0
            if timer then
                timer:begin(0)
            end
            oldShadow(sh, ...)
            if timer then
                timer:finish()
            end
        end
        r.prepare = function(rr, ...)
            oldPrepare(rr, ...)
            if timer then
                timer:begin(1)
            end
        end
        local cube = w.byName['Cube10.2'] or w.byName.ShadowCaster
        local baseY, baseYaw, yaw = cube.position[2], cube.rotation[2], c.rotation[2]
        local lightX = {}
        for j, l in ipairs(w.lights) do
            lightX[j] = l.position[1]
        end

        local function pose(mode, i)
            local t = i / 60
            c.position[1] = ((mode == 'Camera' or mode == 'All') and math.sin(t) * 16 or 0)
            c.rotation[2] = yaw + ((mode == 'Camera' or mode == 'All') and math.sin(t) * 12 or 0)
            if not motion then
                cube.position[2] = baseY
                    + ((mode == 'Cube' or mode == 'All') and math.sin(t * 2) * 18 or 0)
                cube.rotation[2] = baseYaw + ((mode == 'Cube' or mode == 'All') and t * 60 or 0)
                for j, l in ipairs(w.lights) do
                    l.position[1] = lightX[j]
                        + ((mode == 'Lights' or mode == 'All') and math.sin(t * 2 + j) * 16 or 0)
                end
            end
            -- Force the configured update/selection deadline for deterministic paired work.
            r.shadows.nextUpdate = -1
            r.lights.nextSelection = 0
        end
        local cases = zone == 'combined' and { 'Off', 'On' } or { 'Off', 'Sun', 'Spot', 'Point' }
        for _, kind in ipairs(cases) do
            w.environment.shadows.enabled = kind ~= 'Off'
            if zone == 'shadows' then
                s.demo.directionalShadow.enabled = kind == 'Sun'
                for _, l in ipairs(w.lights) do
                    l.castShadow = (kind == 'Spot' and l == s.demo.shadowSpot)
                        or (kind == 'Point' and l == s.demo.shadowPoint)
                end
            end
            for _, mode in ipairs(modes) do
                if motion then
                    if motion.cubeEnabled then
                        motion:toggleCube()
                    end
                    if motion.lightsEnabled then
                        motion:toggleLights()
                    end
                    cube.position[2], cube.rotation[2] = baseY, baseYaw
                    for j, l in ipairs(w.lights) do
                        l.position[1] = lightX[j]
                    end
                    motion.time = 0
                    if mode == 'Cube' or mode == 'All' then
                        motion:toggleCube()
                    end
                    if mode == 'Lights' or mode == 'All' then
                        motion:toggleLights()
                    end
                end
                local totals = {}

                local function add(k, v)
                    totals[k] = (totals[k] or 0) + (v or 0)
                end
                for i = 1, 36 do
                    local start = katsa.timer.getTime()
                    s:update(1 / 60)
                    pose(mode, i)
                    if cube.body then
                        cube.body:teleport(cube.position, cube.rotation)
                    end
                    local updated = katsa.timer.getTime()
                    shadowComparisons, shadowRows = 0, 0
                    local before = katsa.graphics.getStats()
                    r:draw(w, c, i / 60, true)
                    local after = katsa.graphics.getStats()
                    if timer and not r.stats.frameReused then
                        timer:finish()
                    end
                    local submitted = katsa.timer.getTime()
                    local image = r.canvas:newImageData()
                    local finished = katsa.timer.getTime()
                    if i > 24 then
                        add('update', (updated - start) * 1000)
                        add('renderCPU', (submitted - updated) * 1000)
                        add('wait', (finished - submitted) * 1000)
                        add('total', (finished - start) * 1000)
                        for _, key in ipairs({
                            'cacheCheckMilliseconds',
                            'cullingMilliseconds',
                            'lightSelectionMilliseconds',
                            'shadowScanMilliseconds',
                            'shadowBuildMilliseconds',
                            'mainSubmissionMilliseconds',
                            'shadowFaces',
                            'shadowDrawCalls',
                            'shadowCasterTests',
                            'shadowCasterSubmissions',
                        }) do
                            add(key, r.stats[key])
                        end
                        add('comparisons', shadowComparisons)
                        add('rows', shadowRows)
                        add('drawCalls', after.drawcalls - before.drawcalls)
                        add('canvasSwitches', after.canvasswitches - before.canvasswitches)
                        add('shaderSwitches', after.shaderswitches - before.shaderswitches)
                        add('mainRows', r.stats.frameReused and 0 or r.batches.matrixRows)
                        if timer and not r.stats.frameReused then
                            add('gpuShadow', timer:read(0))
                            add('gpuMain', timer:read(1))
                        end
                    end
                    if i == 36 and output then
                        local encoded = image:encode('png')
                        local f = assert(
                            io.open(
                                output .. '/' .. zone .. '-' .. kind .. '-' .. mode .. '.png',
                                'wb'
                            )
                        )
                        f:write(encoded:getString())
                        f:close()
                        encoded:release()
                    end
                    image:release()
                end
                local keys = {}
                for key in pairs(totals) do
                    keys[#keys + 1] = key
                end
                table.sort(keys)
                local row = { zone, kind, mode }
                for _, key in ipairs(keys) do
                    row[#row + 1] = key .. '=' .. string.format('%.4f', totals[key] / 12)
                end
                print(table.concat(row, ' | '))
            end
        end
        r.prepare, r.shadows.update, r.shadows.drawFace = oldPrepare, oldShadow, oldFace
        if timer then
            timer:release()
        end
        -- CPU-only hot systems, same live scene; UI includes its command submission.
        local profile = require('jit.profile')
        local samples = {}
        profile.start('li1', function(thread, count, state)
            local key = state .. ':' .. profile.dumpstack(thread, 'pl;', 3)
            samples[key] = (samples[key] or 0) + count
        end)
        local start = katsa.timer.getTime()
        for i = 1, 120 do
            s:update(1 / 60)
            s.ui:draw()
        end
        profile.stop()
        print('UPDATE_UI', zone, (katsa.timer.getTime() - start) * 1000 / 120)
        local rows = {}
        for key, n in pairs(samples) do
            rows[#rows + 1] = { key, n }
        end
        table.sort(rows, function(a, b)
            return a[2] > b[2]
        end)
        for i = 1, math.min(10, #rows) do
            print('SAMPLE', rows[i][2], rows[i][1])
        end
    end
    katsa.event.quit()
end

return T
