local ipairs = require('source.engine.math.array').ipairs
-- Render-only snapshots; authoritative node transforms and solver queries stay exact.
local Math = require('source.engine.math.math3d')
local Interpolation = {}

function Interpolation.install(Body3D, O, Physics)
    function Physics:setInterpolation(enabled)
        assert(type(enabled) == 'boolean', 'Interpolation must be boolean')
        self.interpolate = enabled
        self._interpolationMode = enabled
        for _, body in ipairs(self.bodies) do
            if enabled then
                body:resetRenderPose()
            else
                body._renderPose = nil
            end
        end
    end

    function Body3D:resetRenderPose()
        local state = self._renderPose
        if not state then
            state = {
                previousPosition = O.Vec3.new(),
                position = O.Vec3.new(),
                previousRotation = O.Quat.new(),
                rotation = O.Quat.new(),
                mixed = O.Quat.new(),
                matrix = O.Mat3.new(),
                world = Math.identity(),
            }
            self._renderPose = state
        end
        state.paused = self.physics.paused
        self.raw:getPositionTo(state.position)
        self.raw:getOrientationTo(state.rotation)
        state.previousPosition:copyFrom(state.position)
        state.previousRotation:copyFrom(state.rotation)
    end

    function Body3D:beginRenderStep()
        if not self._renderPose then
            self:resetRenderPose()
        end
        local s = self._renderPose
        s.previousPosition:copyFrom(s.position)
        s.previousRotation:copyFrom(s.rotation)
    end

    function Body3D:endRenderStep()
        if not self._renderPose then
            self:resetRenderPose()
        end
        self.raw:getPositionTo(self._renderPose.position)
        self.raw:getOrientationTo(self._renderPose.rotation)
    end

    function Body3D:getRenderMatrix()
        if not self.physics.interpolate or self.type == 'Static' then
            return self.object:getWorldMatrix()
        end
        if not self._renderPose then
            self:resetRenderPose()
        end
        if self._renderPose.paused ~= self.physics.paused then
            self:resetRenderPose()
        end
        local s = self._renderPose
        local t = self.physics.paused and 1
            or math.max(0, math.min(1, self.physics.interpolationAlpha or 0))
        local a, b = s.previousRotation, s.rotation
        local dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
        local sign = dot < 0 and -1 or 1
        dot = math.min(1, math.abs(dot))
        local left, right = 1 - t, t
        if dot < 0.9995 then
            local angle = math.acos(dot)
            local divisor = math.sin(angle)
            left, right = math.sin((1 - t) * angle) / divisor, math.sin(t * angle) / divisor
        end
        right = right * sign
        local q = s.mixed
        q.x, q.y, q.z, q.w =
            a.x * left + b.x * right,
            a.y * left + b.y * right,
            a.z * left + b.z * right,
            a.w * left + b.w * right
        local inv = 1 / math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
        q.x, q.y, q.z, q.w = q.x * inv, q.y * inv, q.z * inv, q.w * inv
        local r = s.matrix:fromQuat(q)
        local m = s.world
        local scale = self.initialScale
        local u = self.physics.units
        m[1], m[2], m[3] = r.e00 * scale, r.e01 * scale, r.e02 * scale
        m[5], m[6], m[7] = r.e10 * scale, r.e11 * scale, r.e12 * scale
        m[9], m[10], m[11] = r.e20 * scale, r.e21 * scale, r.e22 * scale
        local p, old = s.position, s.previousPosition
        m[4], m[8], m[12] =
            (old.x + (p.x - old.x) * t) * u,
            (old.y + (p.y - old.y) * t) * u,
            (old.z + (p.z - old.z) * t) * u
        return m
    end
end

return Interpolation
