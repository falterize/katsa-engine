-- IK plugin: skeleton modifiers for 3D rigs.
--
--   local IK = require('source.engine.plugins').require('ik')
--   local arm = IK.TwoBone.new({ root = 'mixamorig:RightArm', mid = 'mixamorig:RightForeArm',
--                                tip = 'mixamorig:RightHand', target = crate, pole = elbowHint })
--   arm:attach(model.animator)        -- runs after animation sampling every pose evaluation
--   arm.influence = 0.75              -- blend between animation (0) and the solve (1)
--   arm.debug = true                  -- chain / target / pole overlay with the bone debug view
--
-- Solvers: TwoBone (analytic limbs), LookAt (head/eyes/turrets, chains with weights and limits),
-- Fabrik (any chain length, optional pole), Ccd (per-joint limits). Write your own by extending
-- IK.SkeletonModifier and implementing `bones()` and `solve(skeleton, dt)`.
return {
    SkeletonModifier = require('./modifier'),
    Skeleton = require('./skeleton'),
    Quat = require('./quat'),
    TwoBone = require('./solvers.twoBone'),
    LookAt = require('./solvers.lookAt'),
    Fabrik = require('./solvers.fabrik'),
    Ccd = require('./solvers.ccd'),
}
