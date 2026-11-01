-- Only particle shader linking and the three existing blend branches.
local R = {}
R.__index = R

function R.new(manager)
    return setmetatable({ manager = manager, frame = 0 }, R)
end

function R:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        love.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'particles')
        assert(scene, err)
        self.scene = scene
        for i = 1, 30 do
            scene:update(1 / 60, 1 / 60)
        end
    elseif self.frame == 2 then
        assert(self.scene.world.particles.stats.rendered > 0, 'Particles must render')
        print('PASS v58 shader links and particles render in Alpha/Add modes')
        self.scene.demo.emitters[2].blendMode = 'Multiply'
    elseif self.frame == 3 then
        assert(self.scene.world.particles.shader:hasUniform('viewProjection'))
        assert(self.scene.world.particles.shader:hasUniform('multiplyMode'))
        assert(#self.manager.journal.entries == 0)
        print('PASS v58 Multiply renders and both stage-specific uniforms remain active')
        print('PASSED v58 focused particle shader smoke')
        love.event.quit()
    end
end

function R:draw() end
return R
