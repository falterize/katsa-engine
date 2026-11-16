-- The `main.lua` of a scene that is meant to be used as a prefab:
--
--   return require('source.engine.scenes.packed.scene').define(function(scene, context)
--       scene.world:create('Mesh3D', { name = 'Crate', size = { 1, 1, 1 } })
--   end)
--
-- `build` runs once, when the scene is packed; whatever it puts under the World3D (and on the
-- scene's World2D overlay) is the prefab. The hooks run for every copy, like the lifecycle of a
-- scene inside the scene that holds the copy (see runtime.lua):
--
--   define(build, {
--       create = function(scene, context) return state end,   -- scene.node is the copy's Node3D
--       update = function(state, dt) end, update2D = ..., update3D = ..., destroy = function(state) end,
--       systems = { aiSystem = { order = 20 } },              -- order of the modules in systems/
--   })
local Prefab = {}

local function nothing() end

function Prefab.define(build, hooks)
    hooks = hooks or {}
    return {
        build = build,
        -- Copies only start scripts when there is something to run (systems/ counts too).
        scripted = next(hooks) ~= nil,
        create = hooks.create or nothing,
        update = hooks.update or nothing,
        update2D = hooks.update2D or nothing,
        update3D = hooks.update3D or nothing,
        destroy = hooks.destroy or nothing,
        systems = hooks.systems,
    }
end

return Prefab
