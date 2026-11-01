local UI = require('source.engine.ui')
local Physics = require('source.engine.physics')
local World = require('source.engine.world.world')
local Display = require('source.engine.core.displayDpi')
local O = require('source.engine.physics.3d.valueTypes')

local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    return setmetatable({ manager = manager, count = 0 }, Tests)
end

function Tests:update() end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v105.2', label)
end

function Tests:display()
    local resources = self.manager.resources:scope()
    local ui = UI.new(1280, 720, resources)
    local button = ui:button(
        { position = { 0, 20, 0, 30 }, size = { 0, 100, 0, 48 }, text = 'Logical pixels' },
        ui.content
    )
    local safeArea, uiScale, graphicsDpi =
        katsa.window.getSafeArea, Display.uiScale, katsa.graphics.getDPIScale
    local ok, message = pcall(function()
        for _, scale in ipairs({ 1, 1.25, 1.5, 2 }) do
            katsa.window.getSafeArea = function()
                return 0, 0, 1280 * scale, 720 * scale
            end
            Display.uiScale = function()
                return scale
            end
            katsa.graphics.getDPIScale = function()
                return 1
            end
            ui:fit(1280 * scale, 720 * scale)
            ui:layout()
            self:check(
                ui.width == 1280 and ui.height == 720,
                'Logical viewport is stable at scale ' .. scale
            )
            self:check(
                ui.scale == scale and ui.density == scale,
                'Geometry and glyph density agree at scale ' .. scale
            )
            self:check(
                button._height == 48 and ui:hit(60 * scale, 50 * scale) == button,
                'Button size and hit testing use the same scale ' .. scale
            )
        end
        katsa.window.getSafeArea = function()
            return 0, 0, 1280, 720
        end
        Display.uiScale = function()
            return 1
        end
        katsa.graphics.getDPIScale = function()
            return 2
        end
        ui:fit(1280, 720)
        self:check(
            ui.width == 1280 and ui.scale == 1 and ui.density == 2,
            'Logical-coordinate Retina/mobile targets do not receive a second DPI scale'
        )
        ui.layoutMode = 'Fit'
        Display.uiScale = function()
            return 2
        end
        ui:fit(1280, 720)
        self:check(ui.scale == 1, 'Reference Fit mode retains proportional viewport fitting')
    end)
    katsa.window.getSafeArea, Display.uiScale, katsa.graphics.getDPIScale =
        safeArea, uiScale, graphicsDpi
    assert(ok, message)
    ui:release()
    resources:release()
end

function Tests:physics()
    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    world.physics = Physics.new({ backend = 'jolt', gravity = { 0, 0, 0 }, workerThreads = 0 })
    local node = world:create('Body3D', { position = { 0, 50, 0 }, size = { 20, 20, 20 } })
    local body, driver = node.body, world.physics.adapter
    body:setVelocity({ 40, 0, 0 })
    world.physics:update(1 / 60)
    self:check(
        body.raw._joltMirrorEpoch ~= driver.poseEpoch,
        'A normal Jolt step does not rebuild unused Oimo geometry'
    )
    local position = body.raw:getPosition()
    self:check(position.x > 0, 'Native pose getters remain current without a mirror refresh')
    body.raw:setLinearVelocity(O.Vec3.new(1, 2, 3))
    body.raw:setAngularVelocity(O.Vec3.new(4, 5, 6))
    local linear, angular = body.raw:getLinearVelocity(), body.raw:getAngularVelocity()
    self:check(
        linear.x == 1
            and linear.y == 2
            and linear.z == 3
            and angular.x == 4
            and angular.y == 5
            and angular.z == 6,
        'Velocity setters invalidate cached state and preserve distinct channels'
    )
    body:teleport({ 80, 50, 0 })
    self:check(
        body.raw:getPosition().x == 4,
        'Teleport immediately invalidates a cached native pose'
    )
    world.physics:update(1 / 60)
    local native = body.raw:getPosition()
    local transform = body.shapes[1].raw:getTransform()
    self:check(
        math.abs(transform:getPosition().x - native.x) < 0.00001,
        'A shape query refreshes the Lua narrow-phase geometry before returning it'
    )
    self:check(
        body.raw._joltMirrorEpoch == driver.poseEpoch,
        'Mirror catches up only when requested'
    )
    world.physics:update(1 / 60)
    driver:setDebugDraw(O.DebugDraw.new())
    driver:debugDraw()
    self:check(
        body.raw._joltMirrorEpoch == driver.poseEpoch,
        'Debug drawing explicitly refreshes current mirror geometry'
    )
    body:setCollider({ shape = 'Sphere', radius = 10 })
    body:setAngularVelocity({ 0, 0, 0 })
    body:teleport({ 80, 50, 0 }, { 0, 0, 0 })
    local replacement = body.shapes[1].raw:getTransform():getPosition()
    self:check(
        math.abs(replacement.x - body.raw:getPosition().x) < 0.00001,
        'Replacement colliders bind their mirror to the live body rather than the candidate'
    )
    local sensor = world:create(
        'Body3D',
        { bodyType = 'Static', isTrigger = true, position = { 120, 50, 0 }, size = { 30, 30, 30 } }
    )
    local entered, exited = 0, 0
    sensor:connect('triggerEntered', function()
        entered = entered + 1
    end)
    sensor:connect('triggerExited', function()
        exited = exited + 1
    end)
    body:setVelocity({ 600, 0, 0 })
    for _ = 1, 20 do
        world.physics:update(1 / 60)
    end
    self:check(
        entered > 0 and exited > 0,
        'Moving native bodies enter and exit exact Lua sensors with lazy mirror updates'
    )
    world:release()
    resources:release()
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:display()
    self:physics()
    print('PASSED ' .. self.count .. ' v105.2 checks')
    katsa.event.quit()
end

return Tests
