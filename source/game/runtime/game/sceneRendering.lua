local Game = {}

function Game:draw()
    self.statsLayer.visible = self.showStats
    if not self.world.activeCamera then
        self.ui.backgroundCanvas = nil
        -- A scene can set `clearColor` (alpha 0 shows the desktop through a transparent window).
        local clear = self.clearColor or { 0.03, 0.04, 0.06, 1 }
        katsa.graphics.clear(clear[1], clear[2], clear[3], clear[4])
        self.statistics:sample()
        self.ui:draw()
        require('source.engine.graphics.debug.orientation').draw(self)
        return
    end
    self.renderer:draw(self.world, self.camera, self.time)
    self.ui.backgroundCanvas = self.renderer.canvas
    if self.pendingShadowProbe then
        self.pendingShadowProbe = nil
        self.shadowProbe = require('source.engine.graphics.debug.shadowProbe').measure(
            self.renderer,
            self.world,
            self.camera,
            self.time,
            3
        )
    end
    self.statistics:sample()
    self.input:draw()
    local uiStamp = self.manager.profiler:begin() or (self.showStats and katsa.timer.getTime())
    self.ui:draw()
    require('source.engine.graphics.debug.orientation').draw(self)
    if uiStamp then
        self.uiMilliseconds = (katsa.timer.getTime() - uiStamp) * 1000
    end
    self.manager.profiler:finish('Screen UI', uiStamp)
    local p = self.manager.profiler
    local r = self.renderer.stats
    p:sample('Render prepare', r.cullingMilliseconds or 0)
    p:sample('Occlusion culling', r.occlusionMilliseconds or 0)
    p:sample('Light selection', r.lightSelectionMilliseconds or 0)
    p:sample('Main submission', r.mainSubmissionMilliseconds or 0)
    p:sample('Shadow build', r.shadowBuildMilliseconds or 0)
    if self.world.particles then
        p:sample('Particles simulation', self.world.particles.stats.updateMilliseconds or 0)
        p:sample('Particles submission', self.world.particles.stats.drawMilliseconds or 0)
    end
    if self.physics then
        p:sample('Physics solver', self.physics.stats.solverMilliseconds or 0)
    end
end

return Game
