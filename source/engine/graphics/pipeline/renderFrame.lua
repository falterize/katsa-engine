local ipairs = require('source.engine.math.array').ipairs
-- Install one cohesive responsibility on the public class.
local RenderFrame = {}

function RenderFrame.install(Renderer)
    function Renderer:draw(world, camera, time, offscreen)
        if not camera then
            return nil
        end
        require('source.engine.animation.skeleton.skinLimits').prepare(world)
        local cacheModule = require('source.engine.graphics.pipeline.frameCache')
        local start = katsa.timer.getTime()
        local dependencies = cacheModule.inspect(self, world, camera, time, offscreen)
        self.stats.cacheCheckPhases = dependencies.timings
        self.stats.scalarGroupsSkipped = dependencies.scalarNodesSkipped or 0
        self.stats.scalarGroupsChecked = dependencies.scalarNodesChecked or 0
        local finished = katsa.timer.getTime()
        local elapsed = (finished - start) * 1000
        self.stats.cacheCheckMilliseconds = elapsed
        local window = self._checkTimingWindow
        if not window then
            window = { start = finished, sum = 0, maximum = 0, count = 0 }
            self._checkTimingWindow = window
        end
        window.sum = window.sum + elapsed
        window.maximum = math.max(window.maximum, elapsed)
        window.count = window.count + 1
        if finished - window.start >= 1 then
            self.stats.cacheCheckAverageMilliseconds = window.sum / window.count
            self.stats.cacheCheckMaxMilliseconds = window.maximum
            window.start, window.sum, window.maximum, window.count = finished, 0, 0, 0
        end
        if self.canvas and cacheModule.reusable(self, world, dependencies) then
            self.stats.frameReused = true
            self.stats.reusedFrames = (self.stats.reusedFrames or 0) + 1
            self.stats.mainTriangles, self.stats.shadowTriangles = 0, 0
            self.stats.depthPrepassMilliseconds, self.stats.depthPrepassTriangles, self.stats.depthPrepassDrawCalls =
                0, 0, 0
            self.stats.occlusionMilliseconds = 0
            self.stats.cullingMilliseconds = 0
            self.stats.updatedMeshes = 0
            self.stats.mainSubmissionMilliseconds = 0
            self.stats.lightSelectionMilliseconds = 0
            self.stats.shadowDrawCalls, self.stats.shadowFaces = 0, 0
            self.stats.shadowCasterTests, self.stats.shadowCasterSubmissions = 0, 0
            self.stats.shadowScanMilliseconds, self.stats.shadowBuildMilliseconds = 0, 0
            if offscreen then
                return self.canvas
            end
            local g = katsa.graphics
            g.push('all')
            g.origin()
            g.setCanvas()
            g.setShader()
            g.setDepthMode()
            g.setMeshCullMode('none')
            g.setWireframe(false)
            g.setScissor()
            g.setStencilTest()
            g.setColor(1, 1, 1, 1)
            g.setBlendMode('alpha', 'premultiplied')
            g.draw(self.canvas)
            g.pop()
            return
        end
        self.stats.frameReused = false
        self.stats.renderedFrames = (self.stats.renderedFrames or 0) + 1
        self.stats.cacheReason = dependencies.reason
        self:prepare(world, camera, time, dependencies)
        local mainStart = katsa.timer.getTime()
        local g = katsa.graphics
        local s = world.debug and world.debug.wireframe and self.wireShader or nil
        g.push('all')
        g.origin()
        g.setScissor()
        g.setStencilTest()
        g.setCanvas({ self.canvas, depthstencil = self.depth })
        g.clear(0.03, 0.04, 0.06, 1, 0, 1)
        g.setDepthMode()
        if not (world.debug and world.debug.wireframe) then
            self:drawSky(world, camera)
        end
        g.setFrontFaceWinding('cw')
        g.setShader(s)
        self.world, self.camera, self.time = world, camera, time
        self.frame = self.frame + 1
        require('source.engine.graphics.pipeline.depthPrepass').draw(self)
        g.setBlendMode('alpha')
        g.setDepthMode('less', true)
        g.setWireframe(false)
        if world.debug and world.debug.wireframe then
            for _, object in ipairs(self.opaque) do
                self:drawItem(object)
            end
        else
            self.batches:draw(self)
        end
        g.setDepthMode('less', false)
        for _, o in ipairs(self.transparent) do
            self:drawItem(o)
        end
        g.setDepthMode()
        g.setMeshCullMode('none')
        g.setWireframe(false)
        g.setShader()
        g.setWireframe(false)
        self.gizmos:draw(world, camera)
        if world.physics then
            world.physics:drawDebug(camera)
        end
        if world.animators then
            require('source.engine.graphics.debug.skeletonDebug').draw(world, camera)
        end
        if self.billboardDebugActive then
            require('source.engine.graphics.debug.billboardDebug').draw(world, camera)
        end
        g.setShader(s)
        for _, o in ipairs(self.top) do
            self:drawItem(o)
        end
        g.setShader()
        g.setDepthMode()
        g.setMeshCullMode('none')
        g.setWireframe(false)
        if offscreen then
            if self.renderOverlay and #(world.uis or {}) > 0 then
                g.setCanvas({ self.canvas, stencil = true })
                g.setScissor()
                g.setStencilTest()
                g.origin()
                for _, ui in ipairs(world.uis) do
                    ui.width, ui.height, ui.scale, ui.offsetX, ui.offsetY =
                        self.width, self.height, 1, 0, 0
                    ui:draw()
                end
            end
            g.pop()
            dependencies.valid = not dependencies.volatile
            self.stats.mainSubmissionMilliseconds = (katsa.timer.getTime() - mainStart) * 1000
            return self.canvas
        end
        g.setCanvas()
        g.setColor(1, 1, 1, 1)
        g.setBlendMode('alpha', 'premultiplied')
        g.draw(self.canvas)
        g.pop()
        dependencies.valid = not dependencies.volatile
        self.stats.mainSubmissionMilliseconds = (katsa.timer.getTime() - mainStart) * 1000
    end
end

return RenderFrame
