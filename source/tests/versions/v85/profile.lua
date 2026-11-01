local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    love.errorhandler = function(message)
        print('FAILED profile ' .. tostring(message))
        os.exit(1)
    end
    love.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    print('DEVICE', love.graphics.getRendererInfo())
    print(
        'case,update,inspect,prepare,lights,shadows,main,render,complete,draws,faces,updated,heapKB'
    )
    for _, mode in ipairs({
        'None',
        'Four',
        'Full',
        'SpatialUI',
        'ShadowStatic',
        'ShadowCube',
        'ShadowLights',
    }) do
        local scene = self.manager:switch(require('source.game.runtime.game').new, 'combined')
        local w, r, c = scene.world, scene.renderer, scene.camera
        local e = w.environment
        e.debug.gizmos.enabled = false
        e.render.frameCache = false
        e.shadows.enabled = mode:find('Shadow') ~= nil
        e.shadows.sourceFadeSeconds = 0
        -- Keep all existing quality values. Only choose which authored sources cast.
        for i, l in ipairs(w.lights) do
            l.enabled = (mode ~= 'None') and (mode ~= 'Four' or i <= 4)
            l.castShadow = i == 1
        end
        if mode == 'SpatialUI' then
            local board = w:create('BillboardUI', {
                name = 'ProfileBillboard',
                adornee = w.objects[2],
                size = { 0, 160, 0, 50 },
                maxDistance = 1000,
            })
            board.ui:text({ text = 'World panel', size = { 1, 0, 1, 0 } }, board.ui.content)
        end
        local cube = w.byName['Cube10.2']
        local base = c.position[1]
        local yaw = c.rotation[2]
        local total = {}
        local n = 0
        for frame = 1, 52 do
            local t = frame / 60
            local start = love.timer.getTime()
            scene:update(1 / 60, 1 / 60)
            if not e.shadows.enabled then
                c.position[1] = base + math.sin(t) * 30
                c.rotation[2] = yaw + math.sin(t) * 5
            end
            if mode == 'ShadowCube' then
                cube.rotation[2] = t * 60
            end
            if mode == 'ShadowLights' then
                w.lights[1].position[1] = math.sin(t) * 30
            end
            if e.shadows.enabled then
                r.shadows.nextUpdate = -1
            end
            local updated = love.timer.getTime()
            local before = love.graphics.getStats().drawcalls
            r:draw(w, c, t, true)
            local drawn = love.timer.getTime()
            local data = r.canvas:newImageData()
            data:release()
            local finish = love.timer.getTime()
            if frame > 28 then
                n = n + 1
                local values = {
                    update = (updated - start) * 1000,
                    inspect = r.stats.cacheCheckMilliseconds,
                    prepare = r.stats.cullingMilliseconds,
                    lights = r.stats.lightSelectionMilliseconds,
                    shadows = r.stats.shadowBuildMilliseconds,
                    main = r.stats.mainSubmissionMilliseconds,
                    render = (drawn - updated) * 1000,
                    complete = (finish - start) * 1000,
                    draws = love.graphics.getStats().drawcalls - before,
                    faces = r.stats.shadowFaces,
                    updated = r.stats.updatedMeshes,
                    heapKB = collectgarbage('count'),
                }
                for key, value in pairs(values) do
                    total[key] = (total[key] or 0) + (value or 0)
                end
            end
        end
        local fields = { mode }
        for _, key in ipairs({
            'update',
            'inspect',
            'prepare',
            'lights',
            'shadows',
            'main',
            'render',
            'complete',
            'draws',
            'faces',
            'updated',
            'heapKB',
        }) do
            fields[#fields + 1] = string.format('%.4f', total[key] / n)
        end
        print(table.concat(fields, ','))
    end
    print('PROFILE COMPLETE')
    love.event.quit()
end

return T
