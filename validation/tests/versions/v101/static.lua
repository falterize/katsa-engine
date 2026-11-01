-- Identical harness is run on the baseline and refactored source trees.
local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    jit.off()
    jit.flush()
    katsa.errorhandler = function(message)
        print('FAILED comparison ' .. tostring(message))
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
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    for _, zone in ipairs({
        'shadows',
        'occlusion',
        'modelLab',
        'platformer',
        'surfaceGallery',
        'uiGallery',
        'animationLab',
        'shaderLab',
        'audioNodes',
        'particles',
    }) do
        katsa.math.setRandomSeed(384)
        math.randomseed(384)
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
        assert(scene, err)
        local env = scene.world.environment
        -- Skeleton debug uses table-key iteration; omit its nondeterministic overlay in pixel comparison.
        scene.world.debug.bones = false
        for _, animator in ipairs(scene.world.animators or {}) do
            animator.debugEnabled = false
        end
        env.render.frameCache = false
        env.shadows.sourceFadeSeconds = 0
        env.shadows.maxUpdateFaces = 195
        env.shadows.resolution = 64
        for i = 1, 12 do
            scene:update(1 / 60, 1 / 60)
        end
        scene.renderer.lights.nextSelection = 0
        scene.renderer.shadows.nextUpdate = -1
        scene.renderer:draw(scene.world, scene.camera, 10, true)
        local data = scene.renderer.canvas:newImageData()
        local digest = katsa.data.encode('string', 'hex', katsa.data.hash('sha256', data:getString()))
        data:release()
        print('FRAME ' .. zone .. ' ' .. digest)
    end
    assert(#self.manager.journal.entries == 0, 'Runtime journal errors during comparison')
    print('PASSED 10 deterministic scene captures')
    katsa.event.quit()
end

return T
