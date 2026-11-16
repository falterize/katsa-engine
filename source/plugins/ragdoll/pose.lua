-- Pose helpers shared by the ragdoll rig: bones in world space and rotations as Euler degrees.
-- Everything works on the ik plugin's Skeleton (model space) and Quat (x, y, z, w).
local M = require('source.engine.math.math3d')
local Affine = require('source.engine.math.affine')
local Quat = require('../ik.quat')

local Pose = {}

local UNIT = { 1, 1, 1 }
local ORIGIN = { 0, 0, 0 }

-- Rotation of the model root in world space (its scale removed).
function Pose.rootRotation(skeleton, out)
    return Quat.fromMatrix(skeleton.rootMatrix, out)
end

-- World position of a bone: x, y, z.
function Pose.position(skeleton, bone)
    return skeleton:toWorld(skeleton:getPosition(bone))
end

-- World rotation of a bone (a new table).
function Pose.rotation(skeleton, bone, rootRotation)
    return Quat.multiply(rootRotation, skeleton:getRotation(bone), {})
end

-- Euler degrees (the engine's node rotation convention) of a quaternion.
function Pose.euler(q)
    return Affine.euler(M.trs(ORIGIN, q, UNIT))
end

-- Rotation of a node from its render matrix (a new table).
function Pose.nodeRotation(node)
    return Quat.fromMatrix(node:getRenderWorldMatrix(), {})
end

-- Sets a bone to a world rotation.
function Pose.setRotation(skeleton, bone, worldRotation, rootRotation)
    skeleton:setRotation(bone, Quat.multiply(Quat.conjugate(rootRotation, {}), worldRotation, {}))
end

return Pose
