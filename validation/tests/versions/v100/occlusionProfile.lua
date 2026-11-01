-- Full manager cycle; current camera/geometry only, no visibility from prior frames.
local T = {}
T.__index = T
local cases = {
    { 'combined-camera-off', 'combined', false, 'camera' },
    { 'combined-camera-on', 'combined', true, 'camera' },
    { 'wall-camera-off', 'occlusion', false, 'camera' },
    { 'wall-camera-on', 'occlusion', true, 'camera' },
    { 'wall-moving-on', 'occlusion', true, 'wall' },
    { 'partial-camera-on', 'occlusion', true, 'partial' },
}

function T.new(manager)
    io.stdout:setvbuf('no')
    jit.off()
    jit.flush()
    katsa.errorhandler = function(m)
        print('FAILED occlusion profile ' .. tostring(m))
        os.exit(1)
    end
    katsa.window.setMode(810, 456, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

local function summary(values)
    table.sort(values)
    local sum = 0
    for _, v in ipairs(values) do
        sum = sum + v
    end
    return string.format(
        '%.3f/%.3f/%.3f/%.3f',
        sum / #values,
        values[math.ceil(#values * 0.5)],
        values[math.ceil(#values * 0.95)],
        values[math.ceil(#values * 0.99)]
    )
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    print('LOVE', katsa.getVersion())
    print('GPU', katsa.graphics.getRendererInfo())
    print('JIT', jit.version, jit.status(), jit.arch)
    print(
        'case,total mean/p50/p95/p99,update,draw CPU,wait+present,occlusion,checks,prepare,hidden,saved triangles,partial triangles,mask bytes,KB growth/retained'
    )
    for _, case in ipairs(cases) do
        if
            not os.getenv('KATSA_OCCLUSION_CASE')
            or os.getenv('KATSA_OCCLUSION_CASE') == case[1]
        then
            katsa.math.setRandomSeed(384)
            math.randomseed(384)
            local scene =
                assert(self.manager:switch(require('source.game.runtime.game').new, case[2]))
            scene.showStats = false
            local env = scene.world.environment
            env.shadows.enabled = false
            env.debug.gizmos.enabled = false
            env.render.occlusionCulling = case[3]
            if case[4] == 'partial' then
                scene.demo.partialPanel.visible = true
                scene.demo.wall.size[1] = 80
            end
            local samples = {}
            for i = 1, 11 do
                samples[i] = {}
            end
            local x, yaw = scene.camera.position[1], scene.camera.rotation[2]
            local memory = 0
            for frame = 1, 90 do
                if case[4] == 'wall' then
                    scene.demo.wall.position[1] = math.sin(frame / 30) * 180
                else
                    scene.camera.position[1] = x + math.sin(frame / 45) * 30
                    scene.camera.rotation[2] = yaw + math.sin(frame / 60) * 5
                end
                local t = katsa.timer.getTime()
                self.manager:update(1 / 60)
                local updated = katsa.timer.getTime()
                self.manager:draw()
                katsa.graphics.flushBatch()
                local drawn = katsa.timer.getTime()
                local image = scene.renderer.canvas:newImageData()
                image:release()
                katsa.graphics.present()
                local finished = katsa.timer.getTime()
                if frame == 30 then
                    collectgarbage('collect')
                    memory = collectgarbage('count')
                end
                if frame > 30 then
                    local s = scene.renderer.stats
                    local values = {
                        (finished - t) * 1000,
                        (updated - t) * 1000,
                        (drawn - updated) * 1000,
                        (finished - drawn) * 1000,
                        s.occlusionMilliseconds or 0,
                        s.cacheCheckMilliseconds or 0,
                        s.cullingMilliseconds or 0,
                        s.occlusionCulled or 0,
                        s.occlusionSavedTriangles or 0,
                        s.occlusionPartialTriangles or 0,
                        scene.renderer.occlusionState and scene.renderer.occlusionState.maskBytes
                            or 0,
                    }
                    for i, v in ipairs(values) do
                        samples[i][#samples[i] + 1] = v
                    end
                end
            end
            local row = { case[1] }
            for i = 1, 11 do
                row[#row + 1] = summary(samples[i])
            end
            local growth = collectgarbage('count') - memory
            collectgarbage('collect')
            row[#row + 1] = string.format('%.1f/%.1f', growth, collectgarbage('count') - memory)
            print(table.concat(row, ','))
        end
    end
    assert(#self.manager.journal.entries == 0, 'Runtime journal errors')
    print('OCCLUSION FULL LOOP COMPLETE')
    katsa.event.quit()
end

return T
