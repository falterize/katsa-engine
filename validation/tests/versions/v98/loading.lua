-- Synchronous scene-entry diagnostic, including the first fully rendered frame.
local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    jit.off()
    jit.flush()
    katsa.errorhandler = function(message)
        print('FAILED loading ' .. tostring(message))
        os.exit(1)
    end
    katsa.window.setMode(810, 456, { vsync = 0, depth = 24, stencil = 8 })
    local self = setmetatable({ manager = manager }, T)

    local function wrap(module, key, label)
        local old = module[key]
        module[key] = function(...)
            local started = katsa.timer.getTime()
            local a, b, c = old(...)
            print('LOAD', label, (katsa.timer.getTime() - started) * 1000)
            return a, b, c
        end
    end
    local Game = require('source.game.runtime.game')
    for _, key in ipairs({ 'loadStress', 'buildUI', 'buildMaterials', 'resize' }) do
        wrap(Game, key, 'Game.' .. key)
    end
    for _, entry in ipairs({
        { 'source.engine.graphics.pipeline.renderer', 'new' },
        { 'source.engine.world.world', 'new' },
        { 'source.engine.import.models', 'load' },
        { 'source.engine.editor.workspace', 'new' },
        { 'source.engine.materials.opacity', 'register' },
    }) do
        wrap(require(entry[1]), entry[2], entry[1] .. '.' .. entry[2])
    end
    local newShader = katsa.graphics.newShader
    katsa.graphics.newShader = function(source, ...)
        local t = katsa.timer.getTime()
        local value = newShader(source, ...)
        print('SHADER', #source, (katsa.timer.getTime() - t) * 1000)
        return value
    end
    return self
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    for _, zone in ipairs({ 'combined', 'animationPhysicsLab', 'combined' }) do
        katsa.math.setRandomSeed(384)
        math.randomseed(384)
        local started = katsa.timer.getTime()
        local scene = assert(self.manager:switch(require('source.game.runtime.game').new, zone))
        local loaded = katsa.timer.getTime()
        self.manager:update(1 / 60)
        self.manager:draw()
        local data = scene.renderer.canvas:newImageData()
        data:release()
        katsa.graphics.present()
        print(
            'ENTRY',
            zone,
            'load',
            (loaded - started) * 1000,
            'first frame',
            (katsa.timer.getTime() - loaded) * 1000
        )
        for frame = 1, 12 do
            scene.camera.rotation[2] = scene.camera.rotation[2] + 10
            self.manager:update(1 / 60)
            self.manager:draw()
            katsa.graphics.present()
        end
    end
    assert(#self.manager.journal.entries == 0, 'Runtime errors')
    print('LOADING COMPLETE')
    katsa.event.quit()
end

return T
