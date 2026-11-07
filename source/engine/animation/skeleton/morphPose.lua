local Pose = require('./pose')

-- Blends the glTF `weights` channels of the active tracks into the blend shapes of a model.
--
-- Same rule as the bone pose: each track contributes by its effective weight (track blend weight
-- times its bone mask for the mesh node); the animated mix replaces the default weights in
-- proportion to the total, so a half-faded clip leaves half of the default shape. A node no
-- active track animates keeps whatever values the game set by hand.
local MorphPose = {}

local buffer = {}

function MorphPose.apply(model, active)
    for _, node in ipairs(model.nodes) do
        local state = node.blendShapes
        if state then
            local total, sum = 0, {}
            for _, track in ipairs(active) do
                local lookup = track.clip._lookup and track.clip._lookup[node]
                local channel = lookup and lookup.weights
                if channel then
                    local mask = next(track.boneMask) and (track.boneMask[node.name] or 0) or 1
                    local weight = math.max(0, math.min(1, track._blendWeight * mask))
                    if weight > 0 then
                        local value = Pose.sample(channel, track.timePosition, buffer)
                        for t = 1, state.count do
                            sum[t] = (sum[t] or 0) + value[t] * weight
                        end
                        total = total + weight
                    end
                end
            end
            if total > 0 then
                local fraction = math.min(1, total)
                for t = 1, state.count do
                    local default = state.defaults[t]
                    state:set(t, sum[t] / total * fraction + default * (1 - fraction))
                end
            end
        end
    end
end

return MorphPose
