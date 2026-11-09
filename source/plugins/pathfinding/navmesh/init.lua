-- NavMesh plugin module: a baked polygon mesh with smooth routes, dynamic obstacles and crowds.
--
--   local mesh = NavMesh.new({ width = 64, depth = 64, cellSize = 2, origin = { -64, -64 } })
--   mesh:load(blockedLayers, heightLayers)               -- or let a NavMap bake do it
--   local path = mesh:findPath({ x, y, z }, { x2, y2, z2 })   -- straight corners, not cells
--   local wall = mesh:addObstacle({ kind = 'box', x = 0, z = 0, halfX = 2, halfZ = 6 })
--   mesh:moveObstacle(wall, 4, 0)                        -- only the touched tiles are rebuilt
--   local crowd = NavMesh.Crowd.new(mesh)                -- agents that follow paths and avoid each other
local Mesh = require('./mesh')

require('./query').install(Mesh)
require('./obstacles').install(Mesh)

Mesh.Crowd = require('./crowd')

return Mesh
