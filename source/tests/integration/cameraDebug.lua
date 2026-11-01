return function(test, scene)
    local physics, demo = scene.physics, scene.demo
    local enabled = physics.debugEnabled
    physics.debugEnabled = true
    for _, camera in ipairs({ demo.first, demo.third, demo.first, demo.third }) do
        camera:update(katsa.graphics.getDimensions())
        local calls, project = 0, camera.project
        camera.project = function(self, point)
            calls = calls + 1
            return project(self, point)
        end
        physics:drawDebug(camera)
        local point = { x = 0, y = 0, z = 0 }
        physics.debugDraw:line(point, point, { x = 1, y = 1, z = 1 })
        test:check(
            calls >= 2 and physics.debugCamera == camera,
            'Physics debug projects through the current camera after a view switch'
        )
        camera.project = nil
    end
    physics.debugEnabled = enabled
    test:check(
        demo.first.parent == demo.head
            and demo.flashlight.parent == demo.head
            and demo.first.position[1] == 0
            and demo.flashlight.position[2] == 0,
        'Head camera and flashlight use local zero offsets under Attachment3D'
    )
end
