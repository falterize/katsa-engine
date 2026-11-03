local pairs = require('source.engine.math.array').pairs
local ipairs = require('source.engine.math.array').ipairs
local O = require('../valueTypes')
local DebugDrawing = {}

function DebugDrawing.install(Physics, Body3D)
    -- Visuals follow the interpolated pose, which trails the solver by up to one fixed step. The
    -- wireframes must use the same pose, otherwise fast bodies seem to drive ahead of their
    -- colliders. Returns a reused list of { raw, x, y, z, qx, qy, qz, qw } in solver units, or
    -- nil when nothing is interpolated.
    function Physics:debugPoses()
        if not self.interpolate or self.paused then
            return nil
        end
        local list = self._debugPoses or {}
        self._debugPoses = list
        local count, units = 0, self.units
        for _, body in ipairs(self.bodies) do
            if body.type ~= 'Static' and body.raw then
                local m = body:getRenderMatrix()
                local q = body._renderPose and body._renderPose.mixed
                if q then
                    count = count + 1
                    local entry = list[count] or {}
                    list[count] = entry
                    entry.raw = body.raw
                    entry.x, entry.y, entry.z = m[4] / units, m[8] / units, m[12] / units
                    entry.qx, entry.qy, entry.qz, entry.qw = q.x, q.y, q.z, q.w
                end
            end
        end
        for i = #list, count + 1, -1 do
            list[i] = nil
        end
        return count > 0 and list or nil
    end

    -- Backends that mirror the solver into a drawing world (Jolt) take the poses directly. Others
    -- draw their live bodies, so the poses are applied for the draw and restored afterwards.
    local function drawAt(self, poses)
        if not poses or self.world.supportsDebugPoses then
            return self.world:debugDraw(poses)
        end
        local position, orientation = O.Vec3.new(), O.Quat.new()
        local saved = {}
        for i, entry in ipairs(poses) do
            local raw = entry.raw
            local old = { position = O.Vec3.new(), orientation = O.Quat.new() }
            raw:getPositionTo(old.position)
            raw:getOrientationTo(old.orientation)
            saved[i] = old
            position:init(entry.x, entry.y, entry.z)
            orientation:init(entry.qx, entry.qy, entry.qz, entry.qw)
            raw:setPosition(position)
            raw:setOrientation(orientation)
        end
        self.world:debugDraw()
        for i, entry in ipairs(poses) do
            entry.raw:setPosition(saved[i].position)
            entry.raw:setOrientation(saved[i].orientation)
        end
    end

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
        drawAt(self, self:debugPoses())
        katsa.graphics.pop()
    end
end

return DebugDrawing
