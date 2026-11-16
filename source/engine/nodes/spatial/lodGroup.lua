local Node = require('../core.baseNode')
local Math = require('../../math.math3d')
local LodSelect = require('../../components.rendering.lodSelect')

-- LODGroup: shows one of its children at a time, by distance or by size on screen.
--
--   local tree = world:create('LODGroup', { mode = 'Distance', distances = { 25, 60, 150 } })
--   world:create('Mesh3D', { name = 'High', geometry = high }, tree)   -- level 0
--   world:create('Mesh3D', { name = 'Mid', geometry = mid }, tree)     -- level 1
--   world:create('Mesh3D', { name = 'Low', geometry = low }, tree)     -- level 2
--
-- The Node3D children, in order, are the levels (0 = most detailed); the group owns their
-- `visible`. `distances` (mode Distance) or `screenSizes` (mode ScreenSize) list where the next level
-- starts: level k+1 begins at the k-th number, and one more number hides the group beyond it. A
-- missing number comes from the size of the group (`radius`, 0 = measured from level 0). Skinned
-- levels that share one skeleton keep playing the same animation whichever is shown. A model file
-- whose nodes are named `<name>`, `<name>-lod1`, `<name>-lod2` is grouped on import (import/autoLod).
local Class = Node.define('LODGroup', 'Node3D')
Class.propertySchema = {
    mode = { options = LodSelect.modes },
    distances = { visibleWhen = { key = 'mode', equals = 'Distance' } },
    screenSizes = { visibleWhen = { key = 'mode', equals = 'ScreenSize' } },
    bias = { min = 0.1, max = 10 },
    hysteresis = { min = 0, max = 0.5 },
    radius = { min = 0 },
    forceLevel = { min = -1 },
    level = {
        readOnly = true,
        get = function(node)
            return node:getLevel()
        end,
    },
}

-- Seconds between two measurements of the size of level 0 (when `radius` is 0).
local RADIUS_INTERVAL = 0.5
-- Used before a camera has been drawn (no viewport size yet).
local FALLBACK_HEIGHT = 720
-- The group position, reused so a frame allocates nothing.
local CENTER = { 0, 0, 0 }

local function distance(a, b)
    return math.sqrt(Math.distanceSquared(a, b))
end

function Class.initialize(self)
    self.mode = self.mode or 'Distance'
    assert(
        self.mode == 'Distance' or self.mode == 'ScreenSize',
        'LODGroup.mode must be Distance or ScreenSize'
    )
    -- Lists are kept as text, as the inspector edits them; tables are accepted and converted.
    self.distances = LodSelect.format(LodSelect.parse(self.distances, 'distances'))
    self.screenSizes = LodSelect.format(LodSelect.parse(self.screenSizes, 'screenSizes'))
    self.bias = self.bias or 1
    self.hysteresis = self.hysteresis or 0.1
    self.radius = self.radius or 0
    self.forceLevel = self.forceLevel or -1
end

function Class.mount(world, properties, parent)
    local node = Node.new('LODGroup', properties, parent)
    node:setProcess(true)
    return node
end

-- The level shown now: 0 is the most detailed, -1 means the whole group is hidden.
function Class:getLevel()
    return self._level or 0
end

-- The Node3D children, cached until the child list changes.
local function levelsOf(self)
    local levels = self._levels or {}
    self._levels = levels
    local children, count = self.children, 0
    local same = true
    for _, child in ipairs(children) do
        if child:isA('Node3D') then
            count = count + 1
            same = same and levels[count] == child
        end
    end
    if same and #levels == count then
        return levels
    end
    for index = #levels, 1, -1 do
        levels[index] = nil
    end
    for _, child in ipairs(children) do
        if child:isA('Node3D') then
            levels[#levels + 1] = child
        end
    end
    self._thresholdKey = nil
    return levels
end

-- Radius of the bounding sphere around the group position that holds level 0 (`radius` property
-- when set). Meshes know their own radius only once they were drawn, so it is measured again now
-- and then.
local function radiusOf(self, levels, dt)
    if self.radius > 0 then
        return self.radius
    end
    self._radiusTimer = (self._radiusTimer or RADIUS_INTERVAL) + dt
    if self._radiusTimer >= RADIUS_INTERVAL and levels[1] then
        self._radiusTimer = 0
        local radius = 0
        local function include(node)
            local p = node.worldPosition or node.position
            local reach = distance(p, CENTER) + (node.radius or 0)
            radius = math.max(radius, reach)
        end
        if levels[1]:isA('Mesh3D') then
            include(levels[1])
        end
        for _, node in ipairs(levels[1]:getDescendants()) do
            if node:isA('Mesh3D') then
                include(node)
            end
        end
        self._radius = math.max(radius, 0.01)
    end
    return self._radius or 1
end

-- The switch points for the current settings; recomputed only when something they depend on changed.
local function thresholdsOf(self, count, radius)
    local list = self.mode == 'Distance' and self.distances or self.screenSizes
    local key = self._thresholdKey
    if
        not key
        or key.mode ~= self.mode
        or key.list ~= list
        or key.count ~= count
        or key.radius ~= radius
    then
        key = { mode = self.mode, list = list, count = count, radius = radius }
        self._thresholdKey = key
        self._thresholds = LodSelect.thresholds(
            self.mode,
            count,
            LodSelect.parse(list, self.mode == 'Distance' and 'distances' or 'screenSizes'),
            radius
        )
    end
    return self._thresholds
end

-- 1-based level for the camera, or count + 1 when hidden; nil while the camera has no view yet.
local function chooseLevel(self, camera, levels, dt)
    local m = self:getWorldMatrix()
    local x, y, z = m[4], m[8], m[12]
    local view = camera.view
    if not view then
        return nil
    end
    CENTER[1], CENTER[2], CENTER[3] = x, y, z
    local radius = radiusOf(self, levels, dt)
    local away = distance(camera.worldPosition or camera.position, CENTER)
    local pixels = 0
    if self.mode == 'ScreenSize' then
        local _, _, depth = Math.transform(view, x, y, z)
        pixels = 2 * radius * camera:pixelsPerUnitAt(math.max(depth, camera.nearClip or 0.001))
    end
    local value = LodSelect.measure(
        self.mode,
        away,
        pixels,
        camera.height or camera.referenceHeight or FALLBACK_HEIGHT,
        self.bias
    )
    local thresholds = thresholdsOf(self, #levels, radius)
    return LodSelect.level(self.mode, value, thresholds, self._current, self.hysteresis)
end

-- Shows level `index` (1-based; past the last = none) and hides the others.
local function show(self, levels, index)
    if self._current == index then
        return
    end
    self._current = index
    self._level = index <= #levels and index - 1 or -1
    for position, node in ipairs(levels) do
        node.visible = position == index
    end
end

function Class:update(dt)
    local levels = levelsOf(self)
    if #levels == 0 then
        return
    end
    local index
    if self.forceLevel >= 0 then
        index = math.min(self.forceLevel + 1, #levels)
    else
        local world = self._sceneWorld
        local camera = world and world.activeCamera
        index = camera and chooseLevel(self, camera, levels, dt or 0) or self._current or 1
    end
    show(self, levels, index)
end

return Class
