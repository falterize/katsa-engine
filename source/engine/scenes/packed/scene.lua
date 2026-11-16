-- The `main.lua` of a scene that is meant to be used as a prefab:
--
--   return require('source.engine.scenes.packed.scene').define(function(scene, context)
--       scene.world:create('Mesh3D', { name = 'Crate', size = { 1, 1, 1 } })
--   end)
--
-- `build` runs once, when the scene is packed; whatever it puts under the World3D is the prefab.
-- It fills in the lifecycle hooks a scene package must have (`hooks` may replace any of them).
local Prefab = {}

local function nothing() end

function Prefab.define(build, hooks)
    hooks = hooks or {}
    return {
        create = function(scene, context)
            return build(scene, context) or {}
        end,
        update = hooks.update or nothing,
        update2D = hooks.update2D or nothing,
        update3D = hooks.update3D or nothing,
        destroy = hooks.destroy or nothing,
    }
end

return Prefab
