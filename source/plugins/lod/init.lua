-- LOD plugin: the LODGroup node (scene conf `plugins = { lod = true }`) and its parts.
--
--   local Lod = require('source.engine.plugins').require('lod')
--   Lod.Select.level('Distance', 40, { 25, 60 }, nil, 0.1)   -- pure level choice
--   Lod.AutoLod.parse('Tree-lod1-col')                        -- 'Tree', 1
--
-- Select: choosing the level (pure functions). Level: fading and shadows of one level's meshes.
-- Billboard: the camera-facing last level. AutoLod: grouping of `-lodN` nodes on model import.
return {
    Select = require('./select'),
    Level = require('./level'),
    Billboard = require('./billboard'),
    AutoLod = require('./autoLod'),
}
