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
    clip._lookup = clip._lookup or {}
    for _, channel in ipairs(clip.channels) do
        assert(channel.node, 'Animation channel has no target node')
        clip._lookup[channel.node] = clip._lookup[channel.node] or {}
        clip._lookup[channel.node][channel.target] = channel
        assert(
            channel.node and self.model.nodes[channel.node.index] == channel.node,
            'Animation '
                .. clip.name
                .. ' targets another skeleton. Retarget or import it for this model.'
        )
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
        properties[key] = value
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

function Animator:update(dt)
    local model = self.model
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
    local count = 0
    for _, track in ipairs(self.tracks) do
        if
            not track.destroyed
            and track.enabled ~= false
            and track.state ~= 'Stopped'
            and track._blendWeight > 0
        then
            count = count + 1
            active[count] = track
        end
    end
    for i = #active, count + 1, -1 do
        active[i] = nil
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
            if path == 'rotation' then
                Pose.normalize(out)
            end
        end
    end
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
                require('../../math.math3d').compose({ 0, 0, 0 }, root.rotation, root.scale)
            local dx, dy, dz = require('../../math.math3d').transform(
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
