-- Worker script of the voxel world: generates terrain and builds chunk meshes off the main thread.
local Terrain = require('terrain')
local Mesher = require('mesher')

-- { cx, cz, seed } -> the chunk's block string.
Actor.on('generate', function(data)
    return Terrain.generate(data.cx, data.cz, data.seed)
end)

-- { blocks, px, nx, pz, nz } -> the 16-high mesh sections and the number of rectangles.
Actor.on('mesh', function(data)
    local sections, faces = Mesher.build(data.blocks, data)
    return { sections = sections, faces = faces }
end)
