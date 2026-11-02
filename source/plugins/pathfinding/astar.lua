-- Generic A*. The search never sees the map: it asks `space` for neighbors and costs.
--
--   space.neighbors(node)        -> iterator or array of neighbor nodes
--   space.cost(from, to)         -> traversal cost (> 0)
--   space.heuristic(node, goal)  -> admissible estimate (never above the true cost)
--   space.key(node)              -> unique string/number identifying a node (default: the node)
--
-- Returns the node list from start to goal and its total cost, or nil, 'no path'. `limit` bounds
-- the number of expanded nodes so a bad query cannot stall a frame.
local Heap = require('./heap')

local AStar = {}

function AStar.search(space, start, goal, limit)
    local key = space.key or function(node)
        return node
    end
    local startKey, goalKey = key(start), key(goal)
    if startKey == goalKey then
        return { start }, 0
    end
    local open, best, parent, nodes, closed =
        Heap.new(), { [startKey] = 0 }, {}, { [startKey] = start }, {}
    open:push(startKey, space.heuristic(start, goal))
    local expanded, maximum = 0, limit or math.huge
    while not open:isEmpty() do
        local currentKey = open:pop()
        if currentKey == goalKey then
            local path, cursor = {}, currentKey
            while cursor ~= nil do
                table.insert(path, 1, nodes[cursor])
                cursor = parent[cursor]
            end
            return path, best[goalKey], expanded
        end
        if not closed[currentKey] then
            closed[currentKey] = true
            expanded = expanded + 1
            if expanded > maximum then
                return nil, 'search limit reached'
            end
            local current = nodes[currentKey]
            for _, neighbor in ipairs(space.neighbors(current)) do
                local neighborKey = key(neighbor)
                if not closed[neighborKey] then
                    local cost = best[currentKey] + space.cost(current, neighbor)
                    if best[neighborKey] == nil or cost < best[neighborKey] then
                        best[neighborKey], parent[neighborKey], nodes[neighborKey] =
                            cost, currentKey, neighbor
                        open:push(neighborKey, cost + space.heuristic(neighbor, goal))
                    end
                end
            end
        end
    end
    return nil, 'no path'
end

return AStar
