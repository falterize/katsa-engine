local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    jit.off()
    jit.flush()
    love.errorhandler = function(message)
        print('FAILED motion compare ' .. tostring(message))
        os.exit(1)
    end
    love.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    for _, zone in ipairs({ 'combined', 'animationPhysicsLab', 'viewports', 'occlusion' }) do
        love.math.setRandomSeed(384)
        math.randomseed(384)
        local scene = assert(self.manager:switch(require('source.game.runtime.game').new, zone))
        scene.world.debug.bones = false
        for _, a in ipairs(scene.world.animators or {}) do
            a.debugEnabled = false
        end
        if zone == 'combined' then
            scene.world.environment.shadows.enabled = false
        end
        -- Shadow deadlines use wall time. Force equal comparison cadence and
        -- disable only source fade for pixel tests, never for performance runs.
        local worlds = { scene.world }
        for _, view in ipairs(scene.demo and scene.demo.views or {}) do
            worlds[#worlds + 1] = view.world
        end
        for _, world in ipairs(worlds) do
            world.environment.shadows.sourceFadeSeconds = 0
        end
        local x = scene.camera.position[1]
        for frame = 1, 60 do
            if zone == 'combined' or zone == 'occlusion' then
                scene.camera.position[1] = x + math.sin(frame / 30) * 15
            end
            self.manager:update(1 / 60)
            for _, world in ipairs(worlds) do
                local renderer = world == scene.world and scene.renderer or world.renderer
                if renderer then
                    renderer.shadows.nextUpdate = 0
                end
            end
            self.manager:draw()
            if frame % 20 == 0 then
                local image = scene.renderer.canvas:newImageData()
                local prefix = os.getenv('KATSA_CAPTURE_PREFIX')
                if prefix and (zone == 'occlusion' or zone == 'animationPhysicsLab') then
                    local encoded = image:encode('png')
                    local file = assert(io.open(prefix .. zone .. '-' .. frame .. '.png', 'wb'))
                    file:write(encoded:getString())
                    file:close()
                    encoded:release()
                end
                local digest =
                    love.data.encode('string', 'hex', love.data.hash('sha256', image:getString()))
                image:release()
                print('FRAME ' .. zone .. ' ' .. frame .. ' ' .. digest)
                if zone == 'animationPhysicsLab' then
                    local numbers = {}

                    local function add(v)
                        numbers[#numbers + 1] = string.format('%.17g', v)
                    end
                    local poseLines = {}
                    local bodies = {}
                    for _, body in ipairs(scene.physics.bodies) do
                        bodies[#bodies + 1] = body
                    end
                    table.sort(bodies, function(a, b)
                        return a.object.name < b.object.name
                    end)
                    for _, body in ipairs(bodies) do
                        local p, q = body.raw:getPosition(), body.raw:getOrientation()
                        add(p.x)
                        add(p.y)
                        add(p.z)
                        add(q.x)
                        add(q.y)
                        add(q.z)
                        add(q.w)
                        poseLines[#poseLines + 1] = string.format(
                            '%s,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g',
                            body.object.name,
                            p.x,
                            p.y,
                            p.z,
                            q.x,
                            q.y,
                            q.z,
                            q.w
                        )
                    end
                    if prefix then
                        local f = assert(io.open(prefix .. 'physics-' .. frame .. '.txt', 'wb'))
                        f:write(table.concat(poseLines, '\n'))
                        f:close()
                    end
                    print(
                        'PHYSICS',
                        frame,
                        love.data.encode(
                            'string',
                            'hex',
                            love.data.hash('sha256', table.concat(numbers, ','))
                        )
                    )
                    numbers = {}
                    for _, node in ipairs(scene.demo.model.nodes) do
                        for i = 1, 16 do
                            add(node.world[i])
                        end
                    end
                    print(
                        'SKELETON',
                        frame,
                        love.data.encode(
                            'string',
                            'hex',
                            love.data.hash('sha256', table.concat(numbers, ','))
                        )
                    )
                    numbers = {}
                    for _, o in ipairs(scene.world.objects) do
                        for i = 1, 16 do
                            add((o.combined or o.matrix)[i])
                        end
                    end
                    print(
                        'MESHES',
                        frame,
                        love.data.encode(
                            'string',
                            'hex',
                            love.data.hash('sha256', table.concat(numbers, ','))
                        )
                    )
                end
                if zone == 'viewports' then
                    for index, view in ipairs(scene.demo.views) do
                        for _, kind in ipairs({ 'world', 'overlay' }) do
                            local canvas = kind == 'world' and view.world.renderer.canvas
                                or view.world.overlayCanvas
                            local image = canvas:newImageData()
                            local hash = love.data.encode(
                                'string',
                                'hex',
                                love.data.hash('sha256', image:getString())
                            )
                            image:release()
                            print(
                                'FRAME viewport-'
                                    .. index
                                    .. '-'
                                    .. kind
                                    .. ' '
                                    .. frame
                                    .. ' '
                                    .. hash
                            )
                        end
                    end
                end
            end
            love.graphics.present()
        end
    end
    assert(#self.manager.journal.entries == 0, 'Runtime journal errors')
    print('PASSED 24 moving/world/viewport-overlay captures')
    love.event.quit()
end

return T
