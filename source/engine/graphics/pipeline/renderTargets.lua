-- Install one cohesive responsibility on the public class.
local RenderTargets = {}

function RenderTargets.install(Renderer)
    function Renderer:resize(w, h)
        local g = love.graphics
        if
            self._requestedWidth == w
            and self._requestedHeight == h
            and self._requestedDensity == self.renderDensity
            and self._requestedMSAA == self.msaa
            and self._requestedPixels == self.maxRenderPixels
            and self._requestedBytes == self.maxRenderBytes
        then
            return
        end
        self._requestedWidth, self._requestedHeight = w, h
        self._requestedDensity, self._requestedMSAA = self.renderDensity, self.msaa
        self._requestedPixels, self._requestedBytes = self.maxRenderPixels, self.maxRenderBytes
        local density, samples = require('source.engine.graphics.quality.renderQuality').resolve(
            w,
            h,
            self.renderDensity,
            self.msaa,
            g.getSystemLimits(),
            self.maxRenderPixels,
            self.maxRenderBytes
        )
        if
            self.width == w
            and self.height == h
            and self.density == density
            and self.plannedMSAA == samples
        then
            return
        end

        local function allocate(msaa)
            local color = g.newCanvas(w, h, { format = 'rgba8', dpiscale = density, msaa = msaa })
            local ok, depth = pcall(
                g.newCanvas,
                w,
                h,
                { format = 'depth24', readable = false, dpiscale = density, msaa = color:getMSAA() }
            )
            if not ok then
                color:release()
                error(depth, 0)
            end
            if color:getMSAA() ~= depth:getMSAA() then
                color:release()
                depth:release()
                error('Color/depth MSAA mismatch', 0)
            end
            g.push('all')
            local bound, message = pcall(g.setCanvas, { color, depthstencil = depth })
            g.pop()
            if not bound then
                color:release()
                depth:release()
                error(message, 0)
            end
            return color, depth
        end
        local ok, color, depth = pcall(allocate, samples)
        if not ok then
            color, depth = allocate(0)
        end
        require('source.engine.graphics.pipeline.depthPrepass').release(self)
        if self.canvas then
            self.canvas:release()
            self.depth:release()
        end
        self.canvas, self.depth = color, depth
        self.width, self.height, self.density, self.plannedMSAA = w, h, density, samples
        self.actualMSAA = color:getMSAA()
        color:setFilter('linear', 'linear')
    end
end

return RenderTargets
