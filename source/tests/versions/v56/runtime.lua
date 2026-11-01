-- Only the reported Night Player camera paths; no broad benchmark suite.
local R = {}
R.__index = R

function R.new(manager)
    return setmetatable({ manager = manager, frame = 0, count = 0 }, R)
end

function R:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v56 ' .. message)
end

local function eyeError(scene)
    local a, b = scene.camera:getWorldPosition(), scene.demo.head:getWorldPosition()
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

function R:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        love.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
        local scene, err =
            self.manager:switch(require('source.game.runtime.game').new, 'nightPlayer')
        assert(scene, err)
        self.scene = scene
        self:check(eyeError(scene) < 0.001, 'First-person camera starts at Head world position')
        for i = 1, 180 do
            scene:update(1 / 60, 1 / 60)
        end
        self:check(
            eyeError(scene) < 0.01 and scene.camera:getWorldPosition()[2] > 15,
            'Parented first-person camera stays above ground without drift for three seconds'
        )
        local target = scene.demo.third
        self:check(
            target.right[1] == nil,
            'Third camera has never rendered before the reproduction'
        )
        scene.camera = scene.world:setCamera(target, 0.25)
        self:check(
            target.right[1] ~= nil,
            'First third-person transition initializes the camera basis'
        )
        for i = 1, 30 do
            scene:update(1 / 60, 1 / 60)
        end
        self:check(
            scene.camera:getWorldPosition()[2] > 20 and target._controller.transition == nil,
            'Third-person transition completes above ground without a crash'
        )
    elseif self.frame == 2 then
        local scene = self.scene
        scene.demo.thirdController:look(120, -40)
        scene:update(0.016, 0.016)

        local function press(text)
            for _, child in ipairs(scene.demo.toolbar.children) do
                if child.text == text then
                    child.onPress()
                    return
                end
            end
            error('Missing live camera button: ' .. text)
        end
        press('First person')
        for i = 1, 30 do
            scene:update(1 / 60, 1 / 60)
        end
        self:check(
            scene.camera == scene.demo.first and eyeError(scene) < 0.01,
            'Live First person button returns the camera to Head'
        )
        local yaw = scene.demo.firstController.yaw
        press('Third person')
        for i = 1, 30 do
            scene:update(1 / 60, 1 / 60)
        end
        self:check(
            math.abs(scene.demo.thirdController.yaw - yaw) < 0.001,
            'Live camera buttons preserve look yaw'
        )
        for i = 1, 4 do
            press('First person')
            scene:update(0.016, 0.016)
            press('Third person')
            scene:update(0.016, 0.016)
        end
        for i = 1, 30 do
            scene:update(1 / 60, 1 / 60)
        end
        self:check(
            scene.camera:getWorldPosition()[2] > 20,
            'Rapid repeated camera switches remain finite and above ground'
        )
        local third = scene.demo.third
        third._controller.pitch, third._controller.yaw = 0, 0
        local origin = scene.demo.head:getWorldPosition()
        local wall = scene.world:create('Body3D', {
            name = 'CameraRegressionWall',
            bodyType = 'Static',
            position = { origin[1], origin[2] + 15, origin[3] - 30 },
        })
        scene.world:create('Collider3D', { shape = 'Box', size = { 60, 80, 4 } }, wall)
        scene.physics:update(1 / 60)
        third._controller:update(0, true)
        local p = third:getWorldPosition()
        self:check(
            p[3] > origin[3] - 28,
            'Third-person radius probes still stop in front of a wall'
        )
        wall:destroy()
        scene.demo.firstController.pitch, scene.demo.firstController.yaw = 0, 0
        scene.camera = scene.world:setCamera(scene.demo.first, 0.25)
        for i = 1, 30 do
            scene:update(1 / 60, 1 / 60)
        end
        self.capture = 'first'
    elseif self.frame == 3 then
        self.scene.camera = self.scene.world:setCamera(self.scene.demo.third, 0.25)
        for i = 1, 30 do
            self.scene:update(1 / 60, 1 / 60)
        end
        self.capture = 'third'
    elseif self.frame == 4 then
        self.scene.demo.head.rotation = { 0, 35, 0 }
        self.scene.demo.firstController:update(0, true)
        local rotation = self.scene.demo.first:getWorldTransform().rotation
        self:check(
            math.abs(rotation[2] - self.scene.demo.firstController.yaw) < 0.001,
            'Follow orientation stays in world coordinates under a rotated Attachment3D'
        )
        self:check(
            #self.manager.journal.entries == 0,
            'Night Player leaves the error journal empty'
        )
        print('PASSED ' .. self.count .. ' Night Player camera checks')
        love.event.quit()
    end
end

function R:draw()
    if not self.capture then
        return
    end
    local name = self.capture
    self.capture = nil
    love.graphics.captureScreenshot(function(image)
        local data = image:encode('png')
        local file =
            io.open(love.filesystem.getSource() .. '/docs/previews/v56/' .. name .. '.png', 'wb')
        if file then
            file:write(data:getString())
            file:close()
        end
        data:release()
        image:release()
    end)
end

return R
