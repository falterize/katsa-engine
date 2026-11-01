-- Matched ON/OFF work; GPU timing is desktop OpenGL-only and separate from CPU submission.
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
    print(
        'zone,shadows,motion,occlusion,updateCPU,renderCPU,sceneCullCPU,occlusionCPU,shadowCPU,mainCPU,shadowGPU,mainGPU,readbackWait,total,meshBefore,meshAfter,mainTriangles,shadowTriangles,culled,drawCalls,shadowFaces,canvasSwitches,shaderSwitches,reused'
    )
    local rows = {}
    for _, zone in ipairs({ 'occlusion', 'combined' }) do
        local scene = self.manager:switch(require('source.game.runtime.game').new, zone)
        local renderer, world, camera = scene.renderer, scene.world, scene.camera
        local environment = world.environment
        environment.gizmos.enabled = false
        environment.shadows.sourceFadeSeconds = 0
        scene.showStats = false
        local timer = require('source.tests.performance.gpuTimer').new()
        local oldPrepare, oldShadows = renderer.prepare, renderer.shadows.update
        renderer.shadows.update = function(shadows, ...)
            if timer then
                timer:begin(0)
            end
            oldShadows(shadows, ...)
            if timer then
                timer:finish()
            end
        end
        renderer.prepare = function(self, ...)
            oldPrepare(self, ...)
            if timer then
                timer:begin(1)
            end
        end
        local baseX, baseYaw = camera.position[1], camera.rotation[2]
        local cube = world.byName['HiddenCube8.1'] or world.byName['Cube10.2']
        local cubeY, cubeYaw = cube.position[2], cube.rotation[2]
        local lightX, lightZ, lightYaw = {}, {}, {}
        for i, light in ipairs(world.lights) do
            lightX[i], lightZ[i], lightYaw[i] =
                light.position[1], light.position[3], light.rotation[2]
        end
        for _, shadows in ipairs({ false, true }) do
            environment.shadows.enabled = shadows
            for _, motion in ipairs({ 'Idle', 'Camera', 'Cube', 'Lights', 'All' }) do
                for _, enabled in ipairs({ false, true }) do
                    environment.render.occlusionCulling = enabled
                    camera.position[1], camera.rotation[2] = baseX, baseYaw
                    cube.position[2], cube.rotation[2] = cubeY, cubeYaw
                    for i, light in ipairs(world.lights) do
                        light.position[1], light.position[3], light.rotation[2] =
                            lightX[i], lightZ[i], lightYaw[i]
                        light.selected = false
                    end
                    renderer.lights = require('source.engine.world.lights').new()
                    renderer.shadows:release()
                    renderer.shadows =
                        require('source.engine.graphics.shadows.shadows').new(scene.resources)
                    renderer.shadows.update = function(shadows, ...)
                        if timer then
                            timer:begin(0)
                        end
                        oldShadows(shadows, ...)
                        if timer then
                            timer:finish()
                        end
                    end
                    renderer.occlusionState = nil
                    if scene.stressMotion then
                        local controls = scene.stressMotion
                        if controls.cubeEnabled then
                            controls:toggleCube()
                        end
                        if controls.lightsEnabled then
                            controls:toggleLights()
                        end
                        controls.time = 0
                        if motion == 'Cube' or motion == 'All' then
                            controls:toggleCube()
                        end
                        if motion == 'Lights' or motion == 'All' then
                            controls:toggleLights()
                        end
                    end
                    local totals = {}

                    local function add(key, value)
                        totals[key] = (totals[key] or 0) + (value or 0)
                    end
                    for i = 1, 36 do
                        local start, t = katsa.timer.getTime(), i / 60
                        scene:update(1 / 60)
                        camera.position[1] = baseX
                            + ((motion == 'Camera' or motion == 'All') and math.sin(t) * 80 or 0)
                        camera.rotation[2] = baseYaw
                            + ((motion == 'Camera' or motion == 'All') and math.sin(t) * 15 or 0)
                        if zone == 'occlusion' then
                            scene.demo.wall.position[1] = (motion == 'All')
                                    and math.sin(t * 2) * 150
                                or 0
                            cube.position[2] = cubeY
                                + (
                                    (motion == 'Cube' or motion == 'All')
                                        and math.sin(t * 2) * 30
                                    or 0
                                )
                            cube.rotation[2] = cubeYaw
                                + ((motion == 'Cube' or motion == 'All') and t * 60 or 0)
                        end
                        for j, light in ipairs(world.lights) do
                            if not scene.stressMotion then
                                light.position[1] = lightX[j]
                                    + (
                                        (motion == 'Lights' or motion == 'All')
                                            and math.sin(t * 2 + j) * 16
                                        or 0
                                    )
                            end
                        end
                        if zone == 'occlusion' and (motion == 'Lights' or motion == 'All') then
                            environment.sun.direction = { -0.4 + math.sin(t) * 0.1, -1, 0.3 }
                        else
                            environment.sun.direction = { -0.4, -1, 0.3 }
                        end
                        renderer.shadows.nextUpdate = -1
                        renderer.lights.nextSelection = 0
                        local updated = katsa.timer.getTime()
                        local before = katsa.graphics.getStats()
                        renderer:draw(world, camera, t, true)
                        if timer and not renderer.stats.frameReused then
                            timer:finish()
                        end
                        local submitted = katsa.timer.getTime()
                        local after = katsa.graphics.getStats()
                        local image = renderer.canvas:newImageData()
                        local finished = katsa.timer.getTime()
                        local shadowGPU, mainGPU = 0, 0
                        if timer and not renderer.stats.frameReused then
                            shadowGPU, mainGPU = timer:read(0), timer:read(1)
                        end
                        if i > 24 then
                            add('updateCPU', (updated - start) * 1000)
                            add('renderCPU', (submitted - updated) * 1000)
                            add('readbackWait', (finished - submitted) * 1000)
                            add('total', (finished - start) * 1000)
                            add('shadowGPU', shadowGPU)
                            add('mainGPU', mainGPU)
                            for _, key in ipairs({
                                'cullingMilliseconds',
                                'occlusionMilliseconds',
                                'shadowBuildMilliseconds',
                                'mainSubmissionMilliseconds',
                                'meshTrianglesBeforeOcclusion',
                                'meshTrianglesAfterOcclusion',
                                'mainTriangles',
                                'shadowTriangles',
                                'occlusionCulled',
                                'shadowFaces',
                            }) do
                                add(key, renderer.stats[key])
                            end
                            add('drawCalls', after.drawcalls - before.drawcalls)
                            add('canvasSwitches', after.canvasswitches - before.canvasswitches)
                            add('shaderSwitches', after.shaderswitches - before.shaderswitches)
                            add('reused', renderer.stats.frameReused and 1 or 0)
                        end
                        image:release()
                    end
                    local keys = {
                        'updateCPU',
                        'renderCPU',
                        'cullingMilliseconds',
                        'occlusionMilliseconds',
                        'shadowBuildMilliseconds',
                        'mainSubmissionMilliseconds',
                        'shadowGPU',
                        'mainGPU',
                        'readbackWait',
                        'total',
                        'meshTrianglesBeforeOcclusion',
                        'meshTrianglesAfterOcclusion',
                        'mainTriangles',
                        'shadowTriangles',
                        'occlusionCulled',
                        'drawCalls',
                        'shadowFaces',
                        'canvasSwitches',
                        'shaderSwitches',
                        'reused',
                    }
                    local fields =
                        { zone, shadows and 'On' or 'Off', motion, enabled and 'On' or 'Off' }
                    for _, key in ipairs(keys) do
                        fields[#fields + 1] = string.format('%.4f', (totals[key] or 0) / 12)
                    end
                    local row = table.concat(fields, ',')
                    print(row)
                    rows[#rows + 1] = row
                end
            end
        end
        renderer.prepare, renderer.shadows.update = oldPrepare, oldShadows
        if timer then
            timer:release()
        end
    end
    katsa.filesystem.write('profile-v79.csv', table.concat(rows, '\n'))
    katsa.event.quit()
end

return T
