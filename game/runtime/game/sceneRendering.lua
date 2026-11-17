local Game = {}

function Game:draw()
    if not self.world.activeCamera then
        self._ui.backgroundCanvas = nil
        self._ui.backgroundRenderer = nil
        -- A scene can set `clearColor` (alpha 0 shows the desktop through a transparent window).
        local clear = self.clearColor or { 0.03, 0.04, 0.06, 1 }
        katsa.graphics.clear(clear[1], clear[2], clear[3], clear[4])
        self:emit('beforeUI')
        self._ui:draw()
        require('source.engine.graphics.debug.orientation').draw(self)
        self:emit('afterUI')
        return
    end
    self.renderer:draw(self.world, self.camera, self.time)
    self._ui.backgroundCanvas = self.renderer.canvas
    -- Shader2D scene hints (depth, velocity, layer passes) read the renderer that drew the 3D.
    self._ui.backgroundRenderer = self.renderer
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
    self:emit('beforeUI')
    self.input:draw()
    local uiStamp = self.manager.profiler:begin() or (self.showStats and katsa.timer.getTime())
    self._ui:draw()
    require('source.engine.graphics.debug.orientation').draw(self)
    self:emit('afterUI')
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
