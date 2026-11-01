-- The same harness runs against both source versions at identical settings.
local T = {}
T.__index = T

function T.new(manager)
    love.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
    local scene = manager:switch(require('source.game.runtime.game').new, 'combined')
    scene.world.environment.shadows.enabled = false
    scene.world.environment.gizmos.enabled = false
    scene.showStats = false
    return setmetatable({ scene = scene }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local s = self.scene
    local r, w, c = s.renderer, s.world, s.camera
    local cube = w.byName['Cube10.2']
    local y, yaw = cube.position[2], c.rotation[2]
    local positions = {}
    for i, l in ipairs(w.lights) do
        positions[i] = l.position[1]
    end

    local function pose(mode, i)
        local t = i / 60
        cube.position[2] = y + (mode == 'Cube' and math.sin(t * 2) * 18 or 0)
        cube.rotation[2] = mode == 'Cube' and t * 60 or 0
        c.rotation[2] = yaw + (mode == 'Camera' and math.sin(t) * 12 or 0)
        for j, l in ipairs(w.lights) do
            l.position[1] = positions[j] + (mode == 'Lights' and math.sin(t * 2 + j) * 16 or 0)
        end
    end
    for _, mode in ipairs({ 'Idle', 'Camera', 'Cube', 'Lights' }) do
        for i = 1, 60 do
            pose(mode, i)
            s:update(1 / 60)
            r:draw(w, c, i / 60, true)
        end
        local fence = r.canvas:newImageData()
        fence:release()
        local start, reused, checks, prepare = love.timer.getTime(), 0, 0, 0
        for i = 61, 180 do
            pose(mode, i)
            s:update(1 / 60)
            r:draw(w, c, i / 60, true)
            reused = reused + (r.stats.frameReused and 1 or 0)
            checks = checks + r.stats.cacheCheckMilliseconds
            prepare = prepare + r.stats.cullingMilliseconds
        end
        print(
            string.format(
                '%s CPU update+3D %.3f ms | checks %.3f | prepare %.3f | reused %d/120',
                mode,
                (love.timer.getTime() - start) * 1000 / 120,
                checks / 120,
                prepare / 120,
                reused
            )
        )
        fence = r.canvas:newImageData()
        fence:release()
        start = love.timer.getTime()
        for i = 181, 204 do
            pose(mode, i)
            s:update(1 / 60)
            r:draw(w, c, i / 60, true)
            local image = r.canvas:newImageData()
            image:release()
        end
        local elapsed = love.timer.getTime() - start
        local output = os.getenv('KATSA_PROFILE_OUTPUT')
        if output then
            local image = r.canvas:newImageData()
            local encoded = image:encode('png')
            local file = assert(io.open(output .. '/' .. mode .. '.png', 'wb'))
            file:write(encoded:getString())
            file:close()
            encoded:release()
            image:release()
        end
        print(
            string.format(
                '%s synchronized update+3D %.3f ms | objects %d/%d lights %d/%d groups %d',
                mode,
                elapsed * 1000 / 24,
                r.stats.objects,
                #w.objects,
                r.stats.lights,
                #w.lights,
                #r.batches.groups
            )
        )
    end
    local inspect = require('source.engine.graphics.pipeline.frameCache').inspect
    for _, mode in ipairs({ 'Idle', 'Camera', 'Cube', 'Lights' }) do
        for i = 1, 60 do
            pose(mode, i)
            r:prepare(w, c, i / 60, inspect(r, w, c, i / 60, true))
        end
        collectgarbage('collect')
        local start = love.timer.getTime()
        for i = 61, 360 do
            pose(mode, i)
            r:prepare(w, c, i / 60, inspect(r, w, c, i / 60, true))
        end
        print(
            string.format(
                '%s preparation-only %.3f ms | comparisons %s matrixRows %s',
                mode,
                (love.timer.getTime() - start) * 1000 / 300,
                tostring(r.batches.comparisons),
                tostring(r.batches.matrixRows)
            )
        )
    end
    local output = os.getenv('KATSA_PROFILE_OUTPUT')
    if output then
        pose('Idle', 240)
        s:update(1 / 60)
        local capture = love.graphics.newCanvas(960, 540)
        love.graphics.push('all')
        love.graphics.setCanvas({ capture, stencil = true })
        love.graphics.clear(0, 0, 0, 0)
        s.ui:draw()
        love.graphics.pop()
        local image = capture:newImageData()
        local encoded = image:encode('png')
        local file = assert(io.open(output .. '/UI.png', 'wb'))
        file:write(encoded:getString())
        file:close()
        encoded:release()
        image:release()
        capture:release()
    end
    pose('Idle', 240)
    for i = 1, 60 do
        s:update(1 / 60)
        s:draw()
    end
    local fence = r.canvas:newImageData()
    fence:release()
    local ok, p = pcall(require, 'jit.profile')
    local samples = {}
    if ok then
        p.start('li1', function(thread, count, state)
            local key = state .. ':' .. p.dumpstack(thread, 'pl;', 3)
            samples[key] = (samples[key] or 0) + count
        end)
    end
    local start = love.timer.getTime()
    for i = 1, 300 do
        s:update(1 / 60)
        s:draw()
    end
    if ok then
        p.stop()
    end
    print(
        string.format(
            'Idle full scene CPU update+draw %.3f ms',
            (love.timer.getTime() - start) * 1000 / 300
        )
    )
    local rows = {}
    for key, count in pairs(samples) do
        rows[#rows + 1] = { key, count }
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    for i = 1, math.min(12, #rows) do
        print('SAMPLE', rows[i][2], rows[i][1])
    end
    love.event.quit()
end

return T
