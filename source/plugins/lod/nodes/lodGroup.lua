local Math = require('source.engine.math.math3d')
local Animator = require('source.engine.nodes.animation.animator')
local LodSelect = require('../select')
local LodLevel = require('../level')
local LodBillboard = require('../billboard')

-- LODGroup: shows one of its children at a time, by distance or by size on screen. Part of the
-- `lod` plugin: the scene needs `plugins = { 'lod' }`.
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
-- whose nodes are named `<name>-lod0`, `<name>-lod1`, `<name>-lod2` is grouped on import
-- (plugin autoLod). The world's quality profile multiplies `bias` (Environment.render.lodBias).
local Definition = {
    base = 'Node3D',
    properties = {
        mode = {
            default = 'Distance',
            options = LodSelect.modes,
            hint = 'Distance switches by camera distance in world units; ScreenSize by how tall '
                .. 'the group looks (fraction of the screen height).',
        },
        distances = {
            default = '',
            hint = 'Where each next level starts, comma separated (for example 25, 60, 150): '
                .. 'level 1 from 25, level 2 from 60, hidden beyond 150. Empty or 0 entries use '
                .. 'defaults from the group radius.',
            visibleWhen = { key = 'mode', equals = 'Distance' },
        },
        screenSizes = {
            default = '',
            hint = 'Screen height fraction below which each next level starts, comma separated, '
                .. 'falling (for example 0.3, 0.1, 0.02); one more entry hides the group below it. '
                .. 'Empty or 0 entries use defaults.',
            visibleWhen = { key = 'mode', equals = 'ScreenSize' },
        },
        bias = {
            default = 1,
            min = 0.1,
            max = 10,
            hint = 'Above 1 lowers the detail sooner (weak devices), below 1 keeps it longer.',
        },
        referenceFov = {
            default = LodSelect.defaultFov,
            min = 0,
            max = 179,
            hint = 'The field of view the distances were set for. A zoomed-in camera counts as '
                .. 'nearer, so zoom keeps its detail. 0 turns this off.',
            visibleWhen = { key = 'mode', equals = 'Distance' },
        },
        hysteresis = {
            default = 0.1,
            min = 0,
            max = 0.5,
            hint = 'A finer level returns only after passing its switch point by this fraction, '
                .. 'so a group on the border does not flicker.',
        },
        radius = {
            default = 0,
            min = 0,
            hint = 'Size of the group for the defaults and for ScreenSize; 0 measures level 0.',
        },
        forceLevel = {
            default = -1,
            min = -1,
            hint = 'Pins one level (0 = most detailed); -1 chooses by the camera.',
        },
        fadeTime = {
            default = 0,
            min = 0,
            max = 5,
            hint = 'Seconds the old and the new level cross-fade; 0 switches at once.',
        },
        animationRates = {
            default = '',
            hint = 'Animator pose rate (per second) for each level, comma separated (for example '
                .. '60, 30, 10). Empty leaves the animation rate alone.',
        },
        shadowLevel = {
            default = -1,
            min = -1,
            integer = true,
            hint = 'The last level that casts shadows; -1 keeps every level as authored.',
        },
        billboardImage = {
            default = '',
            hint = 'An image (with transparency) that becomes a last, flat level which turns to '
                .. 'face the camera.',
        },
        billboardWidth = {
            default = 0,
            min = 0,
            hint = 'Billboard width in world units; 0 uses the group radius.',
            visibleWhen = { key = 'billboardImage', present = true },
        },
        billboardHeight = {
            default = 0,
            min = 0,
            hint = 'Billboard height in world units; 0 uses the group radius.',
            visibleWhen = { key = 'billboardImage', present = true },
        },
        billboardPivot = {
            default = 'Bottom',
            options = { 'Bottom', 'Center' },
            hint = 'Bottom puts the group position at the lower edge (trees), Center in the middle.',
            visibleWhen = { key = 'billboardImage', present = true },
        },
        level = {
            readOnly = true,
            hint = 'The level shown now; -1 when the group is hidden.',
            get = function(node)
                return node:getLevel()
            end,
        },
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

function Definition.initialize(self)
    assert(
        self.mode == 'Distance' or self.mode == 'ScreenSize',
        'LODGroup.mode must be Distance or ScreenSize'
    )
    -- Lists are kept as text, as the inspector edits them; tables are accepted and converted.
    self.distances = LodSelect.format(LodSelect.parse(self.distances, 'distances'))
    self.screenSizes = LodSelect.format(LodSelect.parse(self.screenSizes, 'screenSizes'))
    self.animationRates = LodSelect.format(LodSelect.parse(self.animationRates, 'animationRates'))
end

-- The level shown now: 0 is the most detailed, -1 means the whole group is hidden.
function Definition:getLevel()
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
    self._thresholdKey, self._appliedShadow = nil, nil
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

-- The quality profile's share of the bias (Environment.render.lodBias, 1 without one).
local function qualityBias(self)
    local environment = self._sceneWorld and self._sceneWorld.lighting
    return environment and environment.render and environment.render.lodBias or 1
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
    if camera.projectionMode ~= 'Orthographic' then
        away = away * LodSelect.fovScale(camera.fov, self.referenceFov)
    end
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
        self.bias * qualityBias(self)
    )
    local thresholds = thresholdsOf(self, #levels, radius)
    return LodSelect.level(self.mode, value, thresholds, self._current, self.hysteresis)
end

-- Ends a running cross-fade at once: the old level goes away, both show as authored.
local function finishFade(self)
    local fade = self._fade
    if not fade then
        return
    end
    self._fade = nil
    LodLevel.restoreAlpha(fade.fromMeshes)
    LodLevel.restoreAlpha(fade.toMeshes)
    if fade.from and fade.from ~= fade.to then
        fade.from.visible = false
    end
end

local EMPTY = {}

local function beginFade(self, from, to)
    self._fade = {
        from = from,
        to = to,
        time = 0,
        fromMeshes = from and LodLevel.meshes(from) or EMPTY,
        toMeshes = to and LodLevel.meshes(to) or EMPTY,
    }
    LodLevel.setAlpha(self._fade.toMeshes, 0)
end

local function stepFade(self, dt)
    local fade = self._fade
    fade.time = fade.time + dt
    local alpha = math.min(1, fade.time / self.fadeTime)
    if alpha >= 1 then
        finishFade(self)
        return
    end
    LodLevel.setAlpha(fade.toMeshes, alpha)
    LodLevel.setAlpha(fade.fromMeshes, 1 - alpha)
end

-- Gives the Animator behind level 1 the rate of the shown level; the authored rate comes back
-- once `animationRates` is empty.
local function applyAnimationRate(self, levels, index)
    local animator = self._animator
    if not animator or animator.destroyed then
        animator = levels[1] and Animator.of(levels[1])
        self._animator = animator
    end
    if not animator then
        return
    end
    local rates = LodSelect.parse(self.animationRates, 'animationRates')
    local rate = LodSelect.entry(rates, index)
    if rate then
        animator._lodPoseRate = animator._lodPoseRate or animator.poseRate
        animator.poseRate = math.min(240, math.max(1, rate))
    elseif animator._lodPoseRate then
        animator.poseRate, animator._lodPoseRate = animator._lodPoseRate, nil
    end
end

local function applyShadows(self, levels)
    for position, node in ipairs(levels) do
        local allowed = self.shadowLevel < 0 or position - 1 <= self.shadowLevel
        LodLevel.setShadows(LodLevel.meshes(node), allowed)
    end
    self._appliedShadow = self.shadowLevel
end

-- Shows level `index` (1-based; past the last = none) and hides the others. With `fadeTime` the
-- old level stays until the new one is fully drawn; `instant` skips that (the first choice, which
-- replaces a guess, not something the viewer saw).
local function show(self, levels, index, instant)
    if self._current == index then
        return
    end
    local previous = self._current
    finishFade(self)
    self._current = index
    self._level = index <= #levels and index - 1 or -1
    local fading = self.fadeTime > 0 and previous ~= nil and not instant
    for position, node in ipairs(levels) do
        node.visible = position == index or fading and position == previous
    end
    if fading then
        beginFade(self, levels[previous], levels[index])
    end
    applyAnimationRate(self, levels, index)
    self._appliedRates = self.animationRates
end

-- Keeps the billboard level in step with its properties: built when an image is set, removed when
-- it is cleared, sized and turned to the camera while it is shown.
local function updateBillboard(self, camera)
    local image = self.billboardImage
    if self._billboardImage ~= image then
        if self._billboard then
            self._billboard:destroy()
            self._billboard = nil
        end
        self._billboardImage = image
        if image ~= '' and self._sceneWorld then
            self._billboard = LodBillboard.create(self._sceneWorld, self, image)
        end
        self._levels = nil
    end
    local quad = self._billboard
    if quad and quad.visible and camera then
        local radius = self._radius or 1
        local width, height =
            LodBillboard.size(self.billboardWidth, self.billboardHeight, radius, self.billboardPivot)
        LodBillboard.place(quad, width, height, self.billboardPivot)
        local position = camera.worldPosition or camera.position
        LodBillboard.face(quad, self, position[1], position[3])
    end
end

function Definition:update(dt)
    local camera = self._sceneWorld and self._sceneWorld.activeCamera
    if self.billboardImage ~= self._billboardImage then
        updateBillboard(self, camera)
    end
    local levels = levelsOf(self)
    if #levels == 0 then
        return
    end
    local index
    if self.forceLevel >= 0 then
        index = math.min(self.forceLevel + 1, #levels)
    else
        index = camera and chooseLevel(self, camera, levels, dt or 0)
    end
    show(self, levels, index or self._current or 1, not self._placed)
    self._placed = self._placed or index ~= nil
    if self._appliedShadow ~= self.shadowLevel then
        applyShadows(self, levels)
    end
    if self._appliedRates ~= self.animationRates then
        applyAnimationRate(self, levels, self._current)
        self._appliedRates = self.animationRates
    end
    if self._fade then
        stepFade(self, dt or 0)
    end
    if self._billboard then
        updateBillboard(self, camera)
    end
end

return Definition
