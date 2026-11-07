-- The routes debug section (`Environment.debug.pathfindingPaths`): independent of the grid view.
local Debug = require('./debug')

local Paths = {}

function Paths.draw(world, camera)
    Debug.drawAllPaths(world, camera)
end

return Paths
