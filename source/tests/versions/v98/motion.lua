-- Full manager loop including the first camera transitions and native allocations.
local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    jit.off()
    jit.flush()
    katsa.errorhandler = function(m)
        print('FAILED motion ' .. tostring(m))
        os.exit(1)
    end
    katsa.window.setMode(810, 456, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local allocations, compiles = 0, 0
    local newMesh, newShader = katsa.graphics.newMesh, katsa.graphics.newShader
    katsa.graphics.newMesh = function(format, ...)
        if
            type(format) == 'table'
            and type(format[1]) == 'table'
            and format[1][1] == 'instanceRow1'
        then
            allocations = allocations + 1
        end
        return newMesh(format, ...)
    end
    katsa.graphics.newShader = function(...)
        compiles = compiles + 1
        return newShader(...)
    end
    local started = katsa.timer.getTime()
    local scene = assert(self.manager:switch(require('source.game.runtime.game').new, 'combined'))
    scene.world.environment.shadows.enabled = false
    scene.world.environment.debug.gizmos.enabled = false
    print('ENTER MS', (katsa.timer.getTime() - started) * 1000)
    local totalAllocations, totalCompiles = 0, 0
    print(
        'frame,total ms,update,checks,prepare,main,depth ms,visible,instance allocations,shader compiles,KB'
    )
    local swivel = os.getenv('KATSA_MOTION_PATH') == 'swivel'
    for frame = 1, swivel and 280 or 210 do
        -- Include rest, gradual approach, a turn away and return to the initial view.
        if swivel and frame > 30 then
            scene.camera.rotation[2] = frame <= 50 and (frame - 30) * 8.5
                or frame <= 140 and 170 + math.sin(frame / 10) * 2
                or math.max(0, 170 - (frame - 140) * 1.25)
        elseif frame > 30 then
            scene.camera.position[3] = -120 + math.min(frame - 30, 100) * 2
            scene.camera.rotation[2] = frame <= 130 and 0
                or math.sin((frame - 130) / 80 * math.pi) * 170
        end
        allocations, compiles = 0, 0
        local t = katsa.timer.getTime()
        self.manager:update(1 / 60)
        local updated = katsa.timer.getTime()
        self.manager:draw()
        katsa.graphics.flushBatch()
        local image = scene.renderer.canvas:newImageData()
        image:release()
        katsa.graphics.present()
        local elapsed = (katsa.timer.getTime() - t) * 1000
        local stats = scene.renderer.stats
        totalAllocations = totalAllocations + allocations
        totalCompiles = totalCompiles + compiles
        print(table.concat({
            frame,
            elapsed,
            (updated - t) * 1000,
            stats.cacheCheckMilliseconds or 0,
            stats.cullingMilliseconds or 0,
            stats.mainSubmissionMilliseconds or 0,
            stats.depthPrepassMilliseconds or 0,
            stats.objects or 0,
            allocations,
            compiles,
            collectgarbage('count'),
        }, ','))
    end
    print('TOTAL INSTANCE ALLOCATIONS', totalAllocations, 'SHADER COMPILES', totalCompiles)
    print('MOTION COMPLETE')
    katsa.event.quit()
end

return T
