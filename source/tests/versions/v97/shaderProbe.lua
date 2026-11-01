-- Paired fixed-state diagnostic, separate from full-game-loop FPS measurements.
local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    jit.off()
    jit.flush()
    love.errorhandler = function(message)
        print('FAILED shader probe ' .. tostring(message))
        os.exit(1)
    end
    love.window.setMode(810, 456, { vsync = 0, depth = 24, stencil = 8 })
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
        '%.3f/%.3f/%.3f',
        sum / #values,
        values[math.ceil(#values * 0.5)],
        values[math.ceil(#values * 0.95)]
    )
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local source =
        require('source.engine.graphics.shaderSource').read('assets/shaders/engine/world.glsl')
    local rejection =
        '// Both diffuse and GGX contributions are zero on the unlit hemisphere.\n            if(dot(normal,toward)<=0.0) continue;\n'
    local first, last = assert(source:find(rejection, 1, true))
    local reference = source:sub(1, first - 1) .. source:sub(last + 1)
    print('PROBE GPU', love.graphics.getRendererInfo())
    print('case,reference mean/p50/p95,new mean/p50/p95,pixels equal')
    for _, zone in ipairs({ 'combined', 'shadows', 'animationPhysicsLab' }) do
        love.math.setRandomSeed(384)
        math.randomseed(384)
        local scene = assert(self.manager:switch(require('source.game.runtime.game').new, zone))
        scene.showStats = false
        scene.world.debug.bones = false
        scene.world.environment.shadows.sourceFadeSeconds = 0
        if zone == 'combined' then
            scene.world.environment.shadows.enabled = false
        end
        for _, a in ipairs(scene.world.animators or {}) do
            a.debugEnabled = false
        end
        for _ = 1, 35 do
            self.manager:update(1 / 60)
            self.manager:draw()
            love.graphics.present()
        end
        local r = scene.renderer
        local old = scene.resources:own(love.graphics.newShader(reference))
        local new = scene.resources:own(love.graphics.newShader(source))
        r.forceGeneralShader = true
        r.freezeShadowUpdates = true
        scene.world.environment.render.frameCache = false
        local before, after = {}, {}
        local equal = true
        for pair = 1, 70 do
            local images = {}

            local function sample(shader, values, index)
                r.shader = shader
                local started = love.timer.getTime()
                r:draw(scene.world, scene.camera, scene.time, true)
                local image = r.canvas:newImageData()
                local elapsed = (love.timer.getTime() - started) * 1000
                images[index] = image:getString()
                image:release()
                if pair > 20 then
                    values[#values + 1] = elapsed
                end
            end
            if pair % 2 == 0 then
                sample(old, before, 1)
                sample(new, after, 2)
            else
                sample(new, after, 2)
                sample(old, before, 1)
            end
            equal = equal and images[1] == images[2]
        end
        print(zone .. ',' .. summary(before) .. ',' .. summary(after) .. ',' .. tostring(equal))
        assert(equal, 'A zero-contribution directional rejection changed pixels')
    end
    print('PAIRED SHADER PROBE COMPLETE')
    love.event.quit()
end

return T
