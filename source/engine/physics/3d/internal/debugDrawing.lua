local pairs = require('source.engine.math.array').pairs
local O = require('../valueTypes')
local DebugDrawing = {}

function DebugDrawing.install(Physics, Body3D)
    function Physics:drawDebug(camera)
        if not self.debugEnabled then
            return
        end
        self.debugCamera = camera
        if not self.debugDraw then
            local draw = O.DebugDraw.new()
            draw.wireframe = true
            self.debugDraw = draw
            draw.line = function(_, a, b, color)
                local u, camera = self.units, self.debugCamera
                local ax, ay = camera:project({ a.x * u, a.y * u, a.z * u })
                local bx, by = camera:project({ b.x * u, b.y * u, b.z * u })
                if ax and bx then
                    katsa.graphics.setColor(color.x, color.y, color.z, 0.9)
                    katsa.graphics.line(ax, ay, bx, by)
                end
            end
            draw.triangle = function(_, a, b, c, _, _, _, color)
                draw:line(a, b, color)
                draw:line(b, c, color)
                draw:line(c, a, color)
            end
            self.world:setDebugDraw(draw)
        end
        for key, value in pairs(self._debugSettings) do
            if key ~= 'enabled' and type(value) == 'boolean' then
                self.debugDraw[key] = value
            end
        end
        katsa.graphics.push('all')
        katsa.graphics.setShader()
        self.world:debugDraw()
        katsa.graphics.pop()
    end
end

return DebugDrawing
