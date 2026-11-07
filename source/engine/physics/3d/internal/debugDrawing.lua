local pairs = require('source.engine.math.array').pairs
local ipairs = require('source.engine.math.array').ipairs
local O = require('../valueTypes')
local DebugDrawing = {}

local SOLVER_TINT = { 1, 0.2, 0.85 }

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
            -- Scratch points: the solver calls these callbacks for every wireframe edge, so
            -- nothing here may allocate.
            local pa, pb, pc = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }
            local function project(point, v)
                local u = self.units
                point[1], point[2], point[3] = v.x * u, v.y * u, v.z * u
                return self.debugCamera:project(point)
            end
            local function paint(color)
                local tint = self.debugTint or color
                local r, g, b = tint[1] or tint.x, tint[2] or tint.y, tint[3] or tint.z
                katsa.graphics.setColor(r, g, b, 0.9)
            end
            draw.line = function(_, a, b, color)
                local ax, ay = project(pa, a)
                local bx, by = project(pb, b)
                if ax and bx then
                    paint(color)
                    katsa.graphics.segment(ax, ay, bx, by)
                end
            end
            -- Each corner is projected once and shared by its two edges.
            draw.triangle = function(_, a, b, c, _, _, _, color)
                local ax, ay = project(pa, a)
                local bx, by = project(pb, b)
                local cx, cy = project(pc, c)
                paint(color)
                if ax and bx then
                    katsa.graphics.segment(ax, ay, bx, by)
                end
                if bx and cx then
                    katsa.graphics.segment(bx, by, cx, cy)
                end
                if cx and ax then
                    katsa.graphics.segment(cx, cy, ax, ay)
                end
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
        -- Render: the pose the visuals use, in the usual colours. Solver: the newest physics step
        -- (what contacts and queries really see), always magenta so the two can be told apart.
        -- Both: the two passes over each other.
        local mode = self._debugSettings.poseMode or 'Render'
        if mode == 'Solver' or mode == 'Both' then
            self.debugTint = SOLVER_TINT
            drawAt(self, nil)
            self.debugTint = nil
        end
        if mode ~= 'Solver' then
            drawAt(self, self:debugPoses())
        end
        katsa.graphics.pop()
    end
end

return DebugDrawing
