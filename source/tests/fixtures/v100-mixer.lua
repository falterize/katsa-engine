local Pose=require('source.engine.animation.skeleton.pose')
local Animator={}
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
    self._poseTime = (self._poseTime or 0) + dt
    assert(self.poseRate > 0 and self.poseRate <= 240, 'Animator.poseRate must be within 1..240')
    if self._poseTime < 1 / self.poseRate then
        return
    end
    self._poseStep = self._poseTime
    self._poseTime = self._poseTime % (1 / self.poseRate)
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
    for i = count + 1, #weights do weights[i], lookups[i], masked[i] = nil, nil, nil end
    for i, track in ipairs(active) do masked[i] = next(track.boneMask) ~= nil end
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
                            local value =
                                Pose.sample(channel, track.timePosition, track._buffers[channel])
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
return Animator.update
