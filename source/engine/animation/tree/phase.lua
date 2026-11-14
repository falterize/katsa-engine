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
    return best:phase()
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
    return best:remaining()
end

function Phase.set(node, phase)
    local leaves = {}
    node:collect(leaves)
    for _, leaf in ipairs(leaves) do
        if leaf.track and leaf:duration() > 0 then
            leaf:setPhase(phase)
        end
    end
end

return Phase
