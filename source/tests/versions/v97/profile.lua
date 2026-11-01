-- Deterministic full manager update/draw benchmark. GPU wait is reported separately.
local T = {}
T.__index = T
local cases = {
    { '401-static', 'combined' },
    { '401-camera', 'combined', camera = true },
    { '401-one-moving', 'combined', moving = true },
    { '401-animation', 'combined', animation = true },
    { 'rig-physics', 'animationPhysicsLab' },
    { 'shadows', 'shadows' },
    { 'viewports', 'viewports' },
    { 'ui', 'uiGallery' },
    { '401-stats', 'combined', stats = true },
    { '401-workspace', 'combined', workspace = true },
}

function T.new(manager)
    io.stdout:setvbuf('no')
    love.errorhandler = function(message)
        print('FAILED v96 profile ' .. tostring(message))
        os.exit(1)
    end
    jit.off()
    jit.flush()
    love.window.setMode(810, 456, { vsync = 0, depth = 24, stencil = 8 })
    local self = setmetatable({ manager = manager, animation = 0 }, T)
    local Animator = require('source.engine.nodes.animation.animator')
    local update = Animator.update
    Animator.update = function(animator, dt)
        local started = love.timer.getTime()
        update(animator, dt)
        self.animation = self.animation + (love.timer.getTime() - started) * 1000
    end
    return self
end

function T:update() end

local function summary(samples)
    table.sort(samples)
    local sum = 0
    for _, v in ipairs(samples) do
        sum = sum + v
    end
    return string.format(
        '%.3f/%.3f/%.3f/%.3f',
        sum / #samples,
        samples[math.ceil(#samples * 0.5)],
        samples[math.ceil(#samples * 0.95)],
        samples[math.ceil(#samples * 0.99)]
    )
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    print('LOVE', love.getVersion())
    print('GPU', love.graphics.getRendererInfo())
    print('JIT', jit.version, jit.status(), jit.arch)
    print(
        'case,update mean/p50/p95/p99,draw CPU,wait+present,total,checks,prepare,solver,updated,batch comparisons,main submit,shadow build,occlusion,UI,animation inclusive,KB growth/retained'
    )
    for _, case in ipairs(cases) do
        local selected = os.getenv('KATSA_PROFILE_CASE')
        if not selected or selected == case[1] then
            love.math.setRandomSeed(384)
            math.randomseed(384)
            local scene, err = self.manager:switch(require('source.game.runtime.game').new, case[2])
            assert(scene, err)
            if case.animation then
                local Models = require('source.engine.import.models')
                local model = Models.load('assets/models/characters/xbot.glb', scene.resources)
                Models.instantiate(
                    scene.world,
                    model,
                    { name = 'ProfileRig', position = { 0, 0, 80 } }
                )
                require('source.game.shared.models.proceduralClips').add(model)
                model.animator:transition('Demo Walk', 0)
            end
            scene.showStats = case.stats or false
            if case.workspace then
                scene.workspace:toggle(true)
            end
            if case[2] == 'combined' then
                scene.world.environment.shadows.enabled = false
                scene.world.environment.debug.gizmos.enabled = false
            end
            local x, yaw = scene.camera.position[1], scene.camera.rotation[2]
            self.manager.profiler.enabled = true
            local instructions = {}
            if os.getenv('KATSA_PROFILE_INSTRUCTIONS') == '1' then
                debug.sethook(function()
                    local info = debug.getinfo(2, 'S')
                    local key = info.short_src .. ':' .. info.linedefined
                    instructions[key] = (instructions[key] or 0) + 1
                end, '', 1000)
            end
            local samples = {}
            for i = 1, 14 do
                samples[i] = {}
            end
            collectgarbage('collect')
            local memory = collectgarbage('count')
            for frame = 1, tonumber(os.getenv('KATSA_PROFILE_FRAMES') or 100) do
                if case.camera then
                    scene.camera.position[1] = x + math.sin(frame / 60) * 30
                    scene.camera.rotation[2] = yaw + math.sin(frame / 60) * 5
                end
                if case.moving then
                    local cube = scene.world.byName['Cube10.2']
                    cube.position[2] = math.sin(frame / 30) * 18
                    cube.rotation[2] = frame
                end
                love.event.pump()
                self.animation = 0
                local start = love.timer.getTime()
                self.manager:update(1 / 60)
                local updated = love.timer.getTime()
                self.manager:draw()
                love.graphics.flushBatch()
                local drawn = love.timer.getTime()
                -- Readback fences submitted work; this is not a pure GPU timer.
                local data = scene.renderer.canvas:newImageData()
                data:release()
                love.graphics.present()
                local finished = love.timer.getTime()
                if frame == 30 then
                    collectgarbage('collect')
                    memory = collectgarbage('count')
                end
                if frame > 30 then
                    local r = scene.renderer.stats
                    local values = {
                        (updated - start) * 1000,
                        (drawn - updated) * 1000,
                        (finished - drawn) * 1000,
                        (finished - start) * 1000,
                        r.cacheCheckMilliseconds or 0,
                        r.cullingMilliseconds or 0,
                        scene.physics and scene.physics.stats.solverMilliseconds or 0,
                        r.updatedMeshes or 0,
                        scene.renderer.batches.comparisons or 0,
                        r.mainSubmissionMilliseconds or 0,
                        r.shadowBuildMilliseconds or 0,
                        r.occlusionMilliseconds or 0,
                        self.manager.profiler.samples['Screen UI']
                                and self.manager.profiler.samples['Screen UI'].last
                            or 0,
                        self.animation,
                    }
                    for i, v in ipairs(values) do
                        samples[i][#samples[i] + 1] = v
                    end
                end
            end
            local row = { case[1] }
            for i = 1, 14 do
                row[#row + 1] = summary(samples[i])
            end
            local growth = collectgarbage('count') - memory
            collectgarbage('collect')
            row[#row + 1] = string.format('%.1f/%.1f', growth, collectgarbage('count') - memory)
            debug.sethook()
            print(table.concat(row, ','))
            local order = {}
            for key, count in pairs(instructions) do
                order[#order + 1] = { key, count }
            end
            table.sort(order, function(a, b)
                return a[2] > b[2]
            end)
            for i = 1, math.min(25, #order) do
                print('INSTRUCTIONS', case[1], order[i][1], order[i][2])
            end
        end
    end
    assert(#self.manager.journal.entries == 0, 'Runtime journal errors')
    print('FULL LOOP PROFILE COMPLETE')
    love.event.quit()
end

return T
