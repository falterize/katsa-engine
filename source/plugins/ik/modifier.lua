-- SkeletonModifier: base class of every IK solver. A modifier is attached to an Animator and runs
-- once per pose evaluation, after animation sampling and before the pose matrices are rebuilt,
-- so it edits the freshly animated pose and never accumulates between frames.
--
--   local leg = IK.TwoBone.new({ root = 'LeftUpLeg', mid = 'LeftLeg', tip = 'LeftFoot',
--                                target = footTarget, pole = kneeHint })
--   leg:attach(model.animator)
--   leg.influence = 0.5           -- 0 = pure animation, 1 = full solve
--
-- Subclasses implement `bones()` (every bone the solver may rotate, for influence blending) and
-- `solve(skeleton, dt)`; both see bones in model space through the Skeleton API.
local Skeleton = require('./skeleton')

local Modifier = {}
Modifier.__index = Modifier

function Modifier.extend()
    local class = setmetatable({}, { __index = Modifier })
    class.__index = class
    return class
end

function Modifier.new(settings)
    local self = setmetatable({}, Modifier)
    return self:configure(settings)
end

function Modifier:configure(settings)
    settings = settings or {}
    self.enabled = settings.enabled ~= false
    self.influence = settings.influence or 1
    self.priority = settings.priority or 0
    self.debug = settings.debug == true
    self.target = settings.target
    self.pole = settings.pole
    return self
end

function Modifier:attach(animator)
    assert(animator and animator.addModifier, 'attach() needs an Animator')
    animator:addModifier(self)
    return self
end

function Modifier:detach()
    if self.animator then
        self.animator:removeModifier(self)
    end
    return self
end

-- Reads a point that may be a {x, y, z} table, a spatial node, or a function returning either.
-- Returns world coordinates, or nil when no point is set.
function Modifier.point(value)
    if type(value) == 'function' then
        value = value()
    end
    if value == nil then
        return nil
    end
    if type(value) == 'table' and value.getWorldPosition then
        local p = value:getWorldPosition()
        return p[1], p[2], p[3]
    end
    assert(type(value) == 'table' and #value >= 3, 'IK points must be {x, y, z}, a node or a function')
    return value[1], value[2], value[3]
end

-- Target in model space, or nil.
function Modifier:modelPoint(skeleton, value)
    local x, y, z = Modifier.point(value)
    if x == nil then
        return nil
    end
    return skeleton:toModel(x, y, z)
end

function Modifier:bones()
    return {}
end

function Modifier:solve() end

function Modifier:process(animator, dt)
    local influence = math.max(0, math.min(1, self.influence))
    if not self.enabled or influence <= 0 then
        self._debugPoints = nil
        return
    end
    local skeleton = self._skeleton
    if not skeleton or skeleton.model ~= animator.model then
        skeleton = Skeleton.new(animator.model)
        self._skeleton = skeleton
    end
    skeleton:refresh()
    local nodes, snapshot
    if influence < 1 then
        nodes = skeleton:resolveAll(self:bones())
        snapshot = skeleton:snapshot(nodes, self._snapshot)
        self._snapshot = snapshot
    end
    self:solve(skeleton, dt or 0)
    if nodes then
        skeleton:blend(nodes, snapshot, influence)
    end
    if self.debug then
        self:captureDebug(skeleton)
    end
end

-- Debug points are stored in world space so any camera can draw them later.
function Modifier:captureDebug(skeleton)
    local points = self._debugPoints or {}
    self._debugPoints = points
    local bones = self:bones()
    for i, name in ipairs(bones) do
        local x, y, z = skeleton:getPosition(name)
        local p = points[i] or {}
        p[1], p[2], p[3] = skeleton:toWorld(x, y, z)
        points[i] = p
    end
    for i = #points, #bones + 1, -1 do
        points[i] = nil
    end
    local tx, ty, tz = Modifier.point(self.target)
    self._debugTarget = tx and { tx, ty, tz } or nil
    local px, py, pz = Modifier.point(self.pole)
    self._debugPole = px and { px, py, pz } or nil
end

-- Draws the solved chain (green), the target (red cross) and the pole (blue cross) over the
-- 3D view. Called by the skeleton debug overlay for modifiers with `debug = true`.
function Modifier:drawDebug(camera, g)
    local points = self._debugPoints
    if not points then
        return
    end
    local previous
    g.setColor(0.2, 1, 0.4, 1)
    for _, p in ipairs(points) do
        local x, y = camera:project(p)
        if x then
            g.circle('line', x, y, 4)
            if previous then
                g.line(previous[1], previous[2], x, y)
            end
            previous = { x, y }
        else
            previous = nil
        end
    end
    local function cross(point, r, g1, b)
        local x, y = camera:project(point)
        if x then
            g.setColor(r, g1, b, 1)
            g.line(x - 6, y, x + 6, y)
            g.line(x, y - 6, x, y + 6)
            return x, y
        end
    end
    if self._debugTarget then
        local x, y = cross(self._debugTarget, 1, 0.2, 0.2)
        local last = points[#points]
        local lx, ly
        if last then
            lx, ly = camera:project(last)
        end
        if x and lx then
            g.setColor(1, 0.2, 0.2, 0.5)
            g.line(lx, ly, x, y)
        end
    end
    if self._debugPole then
        cross(self._debugPole, 0.3, 0.5, 1)
    end
end

return Modifier
