-- Playback position of a graph node: the normalised phase (0..1) of the clip that carried the most
-- weight last update. Nodes use it to carry a phase from one clip to the next.
local Phase = {}

function Phase.get(node)
    local leaves = {}
    node:collect(leaves)
    local best, weight = nil, -1
    for _, leaf in ipairs(leaves) do
        local w = leaf.lastWeight or 0
        if w > weight and leaf.track and leaf:duration() > 0 then
            best, weight = leaf, w
        end
    end
    if not best then
        return 0
    end
    local duration = best:duration()
    return (best.track.timePosition % duration) / duration
end

-- Seconds until the dominant clip reaches its end (0 when it has finished).
function Phase.remaining(node)
    local leaves = {}
    node:collect(leaves)
    local best, weight = nil, -1
    for _, leaf in ipairs(leaves) do
        local w = leaf.lastWeight or 0
        if w > weight and leaf.track and leaf:duration() > 0 then
            best, weight = leaf, w
        end
    end
    if not best then
        return 0
    end
    local duration, track = best:duration(), best.track
    local position = best.loop and track.timePosition % duration or math.min(track.timePosition, duration)
    return (duration - position) / math.max(math.abs(track.speed), 1e-6)
end

function Phase.set(node, phase)
    local leaves = {}
    node:collect(leaves)
    for _, leaf in ipairs(leaves) do
        if leaf.track and leaf:duration() > 0 then
            leaf.track.timePosition = phase * leaf:duration()
        end
    end
end

return Phase
