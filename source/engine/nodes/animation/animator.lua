local Array = require('../../math.array')
local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Node = require('../core.baseNode')
local Pose = require('../../animation.skeleton.pose')

local Animator = Node.define('Animator', 'Node')
Animator.propertySchema =
    { debugEnabled = {}, rootMotionEnabled = {}, poseRate = { min = 1, max = 240 } }
function Animator.initialize(self)
    self.poseRate = self.poseRate or 60
    self.tracks = {}
    self.modifiers = {}
    self.controllers = {}
    self.debugEnabled = self.debugEnabled == true
    self.rootMotionEnabled = self.rootMotionEnabled == true
end

function Animator.mount(world, properties, parent)
    local node = Node.new('Animator', properties, parent)
    node._world = world
    node:setProcess(true)
    assert(node.model, 'Animator requires a model instance')
    world.animators = world.animators or {}
    world.animators[#world.animators + 1] = node
    node:onDestroy(function()
        for i, a in ipairs(world.animators) do
            if a == node then
                table.remove(world.animators, i)
                break
            end
        end
    end)
    return node
end

local DEFAULT_MAP = {} -- cache key of a retarget without a boneMap

-- A clip of this model plays as it is; a clip of another skeleton is retargeted onto this one
-- by bone name (see animation/retarget.lua) and cached per clip and bone map.
function Animator:fitClip(clip, settings)
    local model = self.model
    local foreign = false
    for _, channel in ipairs(clip.channels) do
        assert(channel.node, 'Animation channel has no target node')
        if model.nodes[channel.node.index] ~= channel.node then
            foreign = true
            break
        end
    end
    if not foreign then
        return clip
    end
    local options = settings and settings.retarget or {}
    assert(options ~= false, 'Animation ' .. tostring(clip.name) .. ' targets another skeleton')
    self._retargeted = self._retargeted or setmetatable({}, { __mode = 'k' })
    local byClip = self._retargeted[clip] or {}
    self._retargeted[clip] = byClip
    local key = options.boneMap or DEFAULT_MAP
    local cached = byClip[key]
    if not cached then
        local result, message = require('source.engine.animation.retarget').clip(clip, model, options)
        assert(result, 'Animation ' .. tostring(clip.name) .. ': ' .. tostring(message))
        cached = result
        byClip[key] = cached
    end
    return cached
end

function Animator:load(identifier, settings)
    local clip
    if type(identifier) == 'number' then
        clip = self.model.animations[identifier]
    elseif type(identifier) == 'string' then
        for _, c in ipairs(self.model.animations) do
            if c.name == identifier then
                clip = c
                break
            end
        end
    elseif Array.is(identifier) then
        clip = identifier
    end
    assert(clip, 'Unknown animation: ' .. tostring(identifier))
    clip = self:fitClip(clip, settings)
    clip._lookup = clip._lookup or {}
    for _, channel in ipairs(clip.channels) do
        assert(channel.node, 'Animation channel has no target node')
        clip._lookup[channel.node] = clip._lookup[channel.node] or {}
        clip._lookup[channel.node][channel.target] = channel
    end
    local properties = {
        name = clip.name,
        clip = clip,
        _animator = self,
        order = clip.order or 0,
        speed = clip.speed or 1,
        fadeIn = clip.fadeIn or 0,
        fadeOut = clip.fadeOut or 0,
    }
    for key, value in pairs(settings or {}) do
        if key ~= 'retarget' then
            properties[key] = value
        end
    end
    local track = self._world:create('AnimationTrack', properties, self._trackParent or self)
    self.tracks[#self.tracks + 1] = track
    track:onDestroy(function()
        for i, t in ipairs(self.tracks) do
            if t == track then
                table.remove(self.tracks, i)
                break
            end
        end
    end)
    return track
end

function Animator:transition(name, duration)
    local target = self._stateTracks and self._stateTracks[name]
    if
        target
        and not target.destroyed
        and self._stateTrack == target
        and target.state == 'Playing'
    then
        return target
    end
    for _, track in ipairs(self.tracks) do
        if not track.destroyed and track ~= target then
            track:stop(duration or 0.2)
        end
    end
    if not target or target.destroyed then
        target = self:load(name)
        self._stateTracks = self._stateTracks or {}
        self._stateTracks[name] = target
    end
    self._stateTrack = target
    target:play(duration or 0.2)
    return target
end
local posePaths = { 'translation', 'rotation', 'scale' }

local function higher(a, b)
    return a.order > b.order
        or a.order == b.order and (a._creationOrder or 0) < (b._creationOrder or 0)
end

-- Skeleton modifiers (see the `ik` plugin) run after animation sampling and before the pose
-- matrices are rebuilt, ordered by `priority` (lower first), and edit the freshly sampled pose.
function Animator:addModifier(modifier)
    assert(type(modifier.process) == 'function', 'A modifier needs a process(animator, dt) method')
    if modifier.animator and modifier.animator ~= self then
        modifier.animator:removeModifier(modifier)
    end
    for _, existing in ipairs(self.modifiers) do
        if existing == modifier then
            return modifier
        end
    end
    modifier.animator = self
    self.modifiers[#self.modifiers + 1] = modifier
    table.sort(self.modifiers, function(a, b)
        return (a.priority or 0) < (b.priority or 0)
    end)
    return modifier
end

function Animator:removeModifier(modifier)
    for i, existing in ipairs(self.modifiers) do
        if existing == modifier then
            table.remove(self.modifiers, i)
            modifier.animator = nil
            return true
        end
    end
    return false
end

-- Controllers (see animation/tree) run before the tracks advance, so the weights and speeds they
-- set apply to the same pose evaluation. A controller needs update(dt).
function Animator:addController(controller)
    assert(type(controller.update) == 'function', 'A controller needs an update(dt) method')
    for _, existing in ipairs(self.controllers) do
        if existing == controller then
            return controller
        end
    end
    self.controllers[#self.controllers + 1] = controller
    return controller
end

function Animator:removeController(controller)
    for i, existing in ipairs(self.controllers) do
        if existing == controller then
            table.remove(self.controllers, i)
            return true
        end
    end
    return false
end

-- Additive tracks (`track.additive`) add the difference between their pose and a reference on
-- top of the mixed pose: the clip's first frame (default) or the rest pose
-- (`additiveReference = 'rest'`). Rotations compose (`out * reference^-1 * pose`, scaled by the
-- weight), translations and scales add. A `subtract` track removes the difference instead.
local function addDelta(track, node, path, out, rest, weight)
    local lookup = track.clip._lookup[node]
    local channel = lookup and lookup[path]
    if not channel then
        return
    end
    local value = Pose.sample(channel, track.timePosition, track._buffers[channel])
    track._buffers[channel] = value
    local reference = rest
    if track.additiveReference ~= 'rest' then
        track._references = track._references or {}
        reference = track._references[channel]
        if not reference then
            reference = Pose.copy(Pose.sample(channel, 0, {}))
            track._references[channel] = reference
        end
    end
    local sign = track.subtract and -1 or 1
    if path ~= 'rotation' then
        for i = 1, #out do
            out[i] = out[i] + (value[i] - reference[i]) * weight * sign
        end
        return
    end
    local rx, ry, rz, rw = -reference[1], -reference[2], -reference[3], reference[4]
    local vx, vy, vz, vw = value[1], value[2], value[3], value[4]
    -- delta = reference^-1 * value, shortest way round
    local dx = rw * vx + rx * vw + ry * vz - rz * vy
    local dy = rw * vy - rx * vz + ry * vw + rz * vx
    local dz = rw * vz + rx * vy - ry * vx + rz * vw
    local dw = rw * vw - rx * vx - ry * vy - rz * vz
    if dw < 0 then
        dx, dy, dz, dw = -dx, -dy, -dz, -dw
    end
    dx, dy, dz = dx * sign, dy * sign, dz * sign -- the inverse rotation removes the difference
    -- nlerp from the identity towards delta
    dx, dy, dz, dw = dx * weight, dy * weight, dz * weight, 1 - weight + dw * weight
    local length = math.sqrt(dx * dx + dy * dy + dz * dz + dw * dw)
    dx, dy, dz, dw = dx / length, dy / length, dz / length, dw / length
    local ox, oy, oz, ow = out[1], out[2], out[3], out[4]
    out[1] = ow * dx + ox * dw + oy * dz - oz * dy
    out[2] = ow * dy - ox * dz + oy * dw + oz * dx
    out[3] = ow * dz + ox * dy - oy * dx + oz * dw
    out[4] = ow * dw - ox * dx - oy * dy - oz * dz
end

function Animator:update(dt)
    local model = self.model
    for _, controller in ipairs(self.controllers) do
        controller:update(dt)
    end
    for _, track in ipairs(self.tracks) do
        track:advance(dt)
    end
    assert(self.poseRate > 0 and self.poseRate <= 240, 'Animator.poseRate must be within 1..240')
    local interval = 1 / self.poseRate
    -- poseRate budgets pose evaluations per second of wall-clock time. Gating on scaled
    -- simulation time would pose only every 1/(poseRate * timeScale) frames, so a slowed
    -- world would animate at a fraction of the display rate.
    local world = self._world
    self._poseTime = (self._poseTime or 0) + dt
    self._poseWall = (self._poseWall or 0) + (world and world.frameRealDelta or dt)
    if self._poseWall < interval or self._poseTime <= 0 then
        return
    end
    self._poseStep = self._poseTime
    self._poseTime = 0
    self._poseWall = self._poseWall % interval
    self._active = self._active or {}
    local active = self._active
    self._additive = self._additive or {}
    self._additiveWeights = self._additiveWeights or {}
    local additives, additiveWeights = self._additive, self._additiveWeights
    local count, additiveCount = 0, 0
    for _, track in ipairs(self.tracks) do
        if
            not track.destroyed
            and track.enabled ~= false
            and track.state ~= 'Stopped'
            and track._blendWeight > 0
        then
            if track.additive then
                additiveCount = additiveCount + 1
                additives[additiveCount] = track
            else
                count = count + 1
                active[count] = track
            end
        end
    end
    for i = #active, count + 1, -1 do
        active[i] = nil
    end
    for i = #additives, additiveCount + 1, -1 do
        additives[i] = nil
    end
    table.sort(active, higher)
    self._nodeWeights, self._nodeLookups, self._maskedTracks =
        self._nodeWeights or {}, self._nodeLookups or {}, self._maskedTracks or {}
    local weights, lookups, masked = self._nodeWeights, self._nodeLookups, self._maskedTracks
    for i = count + 1, #weights do
        weights[i], lookups[i], masked[i] = nil, nil, nil
    end
    for i, track in ipairs(active) do
        masked[i] = next(track.boneMask) ~= nil
    end
    for _, node in ipairs(model.nodes) do
        -- Bone masks and effective weights are shared by translation/rotation/scale.
        -- Re-evaluate every pose so direct mask, weight and clip edits remain live.
        for i, track in ipairs(active) do
            local mask = masked[i] and (track.boneMask[node.name] or 0) or 1
            local weight = math.max(0, math.min(1, track._blendWeight * mask))
            weights[i] = weight
            lookups[i] = weight > 0 and track.clip._lookup[node] or false
        end
        for i, track in ipairs(additives) do
            local mask = next(track.boneMask) and (track.boneMask[node.name] or 0) or 1
            additiveWeights[i] = math.max(0, math.min(1, track._blendWeight * mask))
        end
        for _, path in ipairs(posePaths) do
            local out = node[path]
            local rest = node.rest[path]
            -- With no contributing channel, the general mixer resolves exactly
            -- to the rest pose. Keep the same arithmetic and quaternion normalization.
            if count == 0 or count == 1 and not (lookups[1] and lookups[1][path]) then
                for i = 1, #rest do
                    out[i] = 0 + rest[i] * 1
                end
            else
                local remaining = 1
                for i = 1, #rest do
                    out[i] = 0
                end
                local index = 1
                local reference = rest
                while index <= #active and remaining > 1e-6 do
                    local priority = active[index].order
                    local total = 0
                    self._sum = self._sum or {}
                    local sum = self._sum
                    for i = 1, #rest do
                        sum[i] = 0
                    end
                    while index <= #active and active[index].order == priority do
                        local track, weight, lookup = active[index], weights[index], lookups[index]
                        index = index + 1
                        if weight > 0 then
                            local channel = lookup and lookup[path]
                            if channel then
                                local value = Pose.sample(
                                    channel,
                                    track.timePosition,
                                    track._buffers[channel]
                                )
                                track._buffers[channel] = value
                                local sign = 1
                                if path == 'rotation' then
                                    local dot = 0
                                    for i = 1, 4 do
                                        dot = dot + value[i] * reference[i]
                                    end
                                    sign = dot < 0 and -1 or 1
                                end
                                for i = 1, #rest do
                                    sum[i] = sum[i] + value[i] * weight * sign
                                end
                                total = total + weight
                            end
                        end
                    end
                    if total > 0 then
                        local fraction = remaining * math.min(1, total)
                        for i = 1, #rest do
                            out[i] = out[i] + sum[i] / total * fraction
                        end
                        remaining = remaining - fraction
                    end
                end
                for i = 1, #rest do
                    out[i] = out[i] + rest[i] * remaining
                end
            end
            for i, track in ipairs(additives) do
                if additiveWeights[i] > 0 then
                    addDelta(track, node, path, out, rest, additiveWeights[i])
                end
            end
            if path == 'rotation' then
                Pose.normalize(out)
            end
        end
    end
    require('source.engine.animation.skeleton.morphPose').apply(model, active)
    if self.rootMotionEnabled then
        local motionTrack
        for _, track in ipairs(active) do
            for _, channel in ipairs(track.clip.channels) do
                local bone = channel.node
                local included = not next(track.boneMask) or (track.boneMask[bone.name] or 0) > 0
                if
                    channel.target == 'translation'
                    and bone.isBone
                    and (not bone.parent or not bone.parent.isBone)
                    and included
                then
                    motionTrack = track
                    break
                end
            end
            if motionTrack then
                break
            end
        end
        self:applyRootMotion(motionTrack)
    end
    for _, modifier in ipairs(self.modifiers) do
        modifier:process(self, self._poseStep)
    end
    model:update(0)
end

function Animator:applyRootMotion(track)
    if not track then
        return
    end
    local channel
    for _, c in ipairs(track.clip.channels) do
        if
            c.target == 'translation'
            and c.node.isBone
            and (not c.node.parent or not c.node.parent.isBone)
        then
            channel = c
            break
        end
    end
    if not channel then
        return
    end
    local node = channel.node
    local position = node.translation
    if self._rootTrack == track then
        local start = Pose.sample(channel, 0)
        local finish = Pose.sample(channel, track.clip.duration)
        local loops = (track._loops or 0) - (self._rootLoops or 0)
        local delta = {}
        for i = 1, 3 do
            delta[i] = position[i] - self._rootPosition[i] + (finish[i] - start[i]) * loops
        end
        if self.rootMotionHandler then
            self.rootMotionHandler(delta, self, self._poseStep)
        else
            local root = self.model.root
            local parent = root
            while parent do
                assert(not parent.body, 'Root motion with physics requires rootMotionHandler')
                parent = parent.parent
            end
            local matrix =
                require('source.engine.math.math3d').compose({ 0, 0, 0 }, root.rotation, root.scale)
            local dx, dy, dz = require('source.engine.math.math3d').transform(
                matrix,
                delta[1],
                delta[2],
                delta[3],
                0
            )
            root.position[1], root.position[2], root.position[3] =
                root.position[1] + dx, root.position[2] + dy, root.position[3] + dz
        end
    end
    self._rootPosition = { unpack(position) }
    self._rootTrack = track
    self._rootLoops = track._loops or 0
    for i = 1, 3 do
        position[i] = node.rest.translation[i]
    end
end

return Animator
