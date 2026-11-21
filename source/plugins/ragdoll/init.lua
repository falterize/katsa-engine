-- Ragdoll plugin: a humanoid skeleton as physical bodies.
--
--   local ragdoll = world:create('Ragdoll3D', { source = characterBody }, modelRoot)
--   ragdoll.active = true             -- the animated pose becomes a ragdoll
--   ragdoll:getBody('Hips')           -- the Body3D of a segment (follow it with a camera)
--   ragdoll.active = false            -- back to the animation
--
-- The Ragdoll3D node sits under a model instance (the node `Models.instantiate` returns), like
-- InverseKinematics3D, and needs `plugins = { ragdoll = true }` in the scene conf.lua.
return {
    Humanoid = require('./humanoid'),
    Rig = require('./rig'),
}
