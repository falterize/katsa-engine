-- Engine Euler angles for a car with the model's heading (forward = sin, cos), nose-up pitch and
-- right-side-up roll. Engine yaw runs opposite to the heading and pitch is nose-down positive;
-- the rotations apply heading first, then pitch, then roll in the car's own frame.
local Math = require('source.engine.math.math3d')
local Affine = require('source.engine.math.affine')

local ZERO, ONE = { 0, 0, 0 }, { 1, 1, 1 }
local matrices = { {}, {}, {}, {}, {}, {} }
local rotationA, rotationB, rotationC = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }

return function(heading, pitch, roll, out)
    rotationA[2] = -heading
    rotationB[1] = -pitch
    rotationC[3] = roll
    local yaw = Math.compose(ZERO, rotationA, ONE, matrices[1])
    local tilt = Math.compose(ZERO, rotationB, ONE, matrices[2])
    local lean = Math.compose(ZERO, rotationC, ONE, matrices[3])
    local m = Math.multiply(Math.multiply(yaw, tilt, matrices[4]), lean, matrices[5])
    return Affine.euler(Affine.rotation(m, matrices[6]), out or {})
end
