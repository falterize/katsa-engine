-- Worker script of the voxel world: generates terrain and builds chunk meshes off the main thread.
local Terrain = require('terrain')
local Mesher = require('mesher')

-- { cx, cz, seed } -> the chunk's block string.
Actor.on('generate', function(data)
    return Terrain.generate(data.cx, data.cz, data.seed)
end)

-- { blocks, px, nx, pz, nz } -> flat vertex array of the visible faces and their count.
Actor.on('mesh', function(data)
    local vertices, faces = Mesher.build(data.blocks, data)
    return { vertices = vertices, faces = faces }
end)
