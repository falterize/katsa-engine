local Application = require('source.game.runtime.application')
local Plane = require('source.engine.ui.spatial.plane')

local Tests = {}

-- The camera must follow the pose that is drawn (interpolated), not the last solver pose;
-- otherwise interpolated spatial visuals oscillate against the camera between fixed steps.
function Tests.cameraFollowsRenderedPose(tester, frameDelta, label)
    local scene = Application.new(tester.manager, 'abilityRunner2D')
    scene:load()
    local state, ui = scene.demo, scene.ui
    local camera = ui.currentCamera
    local physics = state.player.body.physics
    local worst, checked = 0, 0
    state.player.body:setLinearVelocity(160, 0)
    for _ = 1, 90 do
        scene:update(frameDelta, frameDelta)
        local rx, ry = Plane.pose(state.player)
        local cx, cy = camera:getWorldPose()
        worst = math.max(worst, math.abs(cx - camera.offset[1] - rx), math.abs(cy - camera.offset[2] - ry))
        checked = checked + 1
    end
    tester:check(
        physics.interpolate and checked == 90 and worst < 1e-6,
        label .. ': Camera2D follows the rendered pose (max error ' .. worst .. ')'
    )
    scene:release()
end

function Tests.run(tester)
    Tests.cameraFollowsRenderedPose(tester, 1 / 144, '144 Hz frames')
    Tests.cameraFollowsRenderedPose(tester, 1 / 60 / 4, 'Slow-motion frames')
end

return Tests
