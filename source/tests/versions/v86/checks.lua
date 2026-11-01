local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED checks ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local scene = self.manager:switch(require('source.game.runtime.game').new, 'combined')
    local w, r, c = scene.world, scene.renderer, scene.camera
    w.environment.shadows.enabled = false
    for i = 1, 3 do
        r:draw(w, c, 1, true)
    end
    local cache = require('source.engine.graphics.pipeline.frameCache')
    local cube = w.byName['Cube10.2']
    print('CHECKS JIT', jit.status(), jit.arch)

    local function measure(label)
        local sums = {}
        local count = 400
        for i = 1, 60 do
            cube.rotation[2] = i
            cache.inspect(r, w, c, i / 60, true)
        end
        collectgarbage('collect')
        local start = katsa.timer.getTime()
        for i = 1, count do
            cube.rotation[2] = i
            local deps = cache.inspect(r, w, c, i / 60, true)
            for key, value in pairs(deps.timings) do
                sums[key] = (sums[key] or 0) + value
            end
        end
        print(
            string.format('%s total %.4f ms', label, (katsa.timer.getTime() - start) * 1000 / count)
        )
        for _, key in ipairs({
            'guards',
            'objects',
            'lights',
            'directionalLights',
            'shaderNodes',
            'other',
        }) do
            print(string.format('%s %s %.4f ms', label, key, (sums[key] or 0) / count))
        end
    end
    measure('JIT')
    jit.off()
    jit.flush()
    measure('INTERPRETER')
    jit.on()
    print('CHECKS COMPLETE')
    katsa.event.quit()
end

return T
