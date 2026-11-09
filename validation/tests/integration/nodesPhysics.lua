return function(test)
    local Node = require('source.engine.nodes')
    local Physics = require('source.engine.physics')
    local Resources = require('source.engine.core.resources')
    local UI = require('source.engine.ui')
    local parent = Node.new(
        'Node3D',
        { position = { 10, 20, 30 }, rotation = { 0, 90, 0 }, size = { 2, 2, 2 } }
    )
    local attachment = parent:attachment({ position = { 5, 0, 0 } })
    local position = attachment:getWorldPosition()
    test:check(
        math.abs(position[3] - 35) < 0.001 and position[1] == 10,
        'Attachment3D inherits rotation without visual mesh scale'
    )
    test:check(not pcall(function()
        parent.parent = attachment
    end), 'Node reparent rejects hierarchy cycles')
    local other = Node.new('Folder', {})
    attachment.parent = other
    test:check(
        #parent.children == 0 and other.children[1] == attachment,
        'Direct parent assignment reparents child'
    )
    local cleaned = false
    attachment:onDestroy(function()
        cleaned = true
    end)
    other:destroy()
    test:check(
        cleaned and attachment.destroyed,
        'Destroy releases descendants and cleanup handlers'
    )
    local resources = Resources.new(require('source.game.data.manifest'))
    local ui = UI.new(1280, 720, resources)
    local panel = ui:create('ScrollFrame', {
        position = UI.udim2(1, -20, 0.5, 0),
        anchorPoint = { 1, 0.5 },
        width = 200,
        height = 100,
        length = 400,
    }, ui.content)
    local button =
        ui:create('Button', { x = 10, y = 220, width = 100, height = 40, text = 'Scroll' }, panel)
    ui:create('UICorner', { cornerRadius = 18 }, button)
    ui:layout()
    test:check(
        panel._x == 1060 and panel._y == 310,
        'UI position scale and anchor point resolve correctly'
    )
    test:check(ui:hit(1100, 550) == nil, 'Scroll clips offscreen child hit testing')
    ui:scrollBy(panel, 200)
    ui:layout()
    test:check(
        ui:hit(1100, 345) == button and button._radius == 18,
        'Scrolling reveals button with UICorner node'
    )
    local cornerUI = UI.new(64, 64, resources)
    local rounded = cornerUI:create(
        'Frame',
        { x = 8, y = 8, width = 48, height = 48, color = { 1, 0, 0, 1 } },
        cornerUI.content
    )
    cornerUI:create(
        'ImageRect',
        { width = 48, height = 48, image = 'white', tint = { 0, 1, 0, 1 } },
        rounded
    )
    cornerUI:create('UICorner', { cornerRadius = 18 }, rounded)
    local canvas = katsa.graphics.newCanvas(64, 64)
    katsa.graphics.push('all')
    katsa.graphics.setCanvas({ canvas, stencil = true })
    katsa.graphics.clear(0, 0, 1, 1)
    cornerUI:draw()
    katsa.graphics.setCanvas()
    katsa.graphics.pop()
    local pixels = canvas:newImageData()
    local r, g, b = pixels:getPixel(8, 8)
    local _, center = pixels:getPixel(32, 32)
    test:check(
        b > 0.95 and g < 0.02 and center > 0.95,
        'UICorner clips images and child UI using stencil'
    )
    pixels:release()
    canvas:release()
    cornerUI:release()
    local Input = require('source.engine.input.input')
    local input = Input.new({ ui = ui })
    local clicks = 0
    button.onPress = function()
        clicks = clicks + 1
    end
    input:press('scroll', 1100, 345)
    input:move('scroll', 1100, 315, 0, -30)
    input:release('scroll')
    test:check(
        clicks == 0 and panel.scrollY == 230,
        'Dragging a scroll button scrolls without activating it'
    )
    input:press('tap', 1100, 320)
    input:release('tap')
    test:check(clicks == 1, 'Tap in scrolling UI activates button on release')
    input:reset()
    local physics = Physics.new()
    local world = Node.new('World3D', { position = { 0, 0, 0 } })
    local floor = Node.new('Mesh3D', { position = { 0, -5, 0 }, size = { 200, 10, 200 } }, world)
    physics:addBody(floor, { type = 'Static', friction = 0.8 })
    local cube = Node.new('Mesh3D', { position = { 0, 60, 0 }, size = { 20, 20, 20 } }, world)
    local body = physics:addBody(cube, { density = 2 })
    for i = 1, 180 do
        physics:update(1 / 60)
    end
    test:check(
        math.abs(cube.position[2] - 10) < 0.3,
        '3D rigid cube falls, collides and settles on ground'
    )
    test:check(
        math.abs(body:getMass() - 2) < 0.001,
        'Body3D density determines mass from collider volume'
    )
    body.properties.density = 4
    physics:update(1 / 60)
    test:check(
        math.abs(body:getMass() - 4) < 0.001,
        'Direct physics property assignment updates mass'
    )
    body.properties.mass = 5
    physics:update(1 / 60)
    test:check(
        math.abs(body:getMass() - 5) < 0.001,
        'Custom mass property overrides density and scales inertia'
    )
    body:set({ friction = 0.1, restitution = 0.8, linearDamping = 0.3 })
    test:check(
        body.shapes[1].raw:getFriction() == 0.1 and body.raw:getLinearDamping() == 0.3,
        'Runtime friction restitution and damping setters'
    )
    local hit = physics:raycast({ 0, 100, 0 }, { 0, -20, 0 })
    test:check(hit and hit.body == body, '3D raycast returns body and surface position')
    physics:addGroup('ghost')
    physics:setGroupsCollidable('ghost', 'default', false)
    body:set({ collisionGroup = 'ghost' })
    body:teleport({ 0, 60, 0 })
    body:setVelocity({ 0, 0, 0 })
    for i = 1, 120 do
        physics:update(1 / 60)
    end
    test:check(cube.position[2] < -50, 'Named collision groups disable ghost-ground contact')
    body:set({ collisionGroup = 'default', canQuery = false })
    body:teleport({ 0, 60, 0 })
    hit = physics:raycast({ 0, 100, 0 }, { 0, -20, 0 })
    test:check(
        hit and hit.body.object == floor,
        'canQuery excludes a body independently from rendering'
    )
    local sphere = Node.new('Mesh3D', { position = { 40, 80, 0 }, size = { 20, 20, 20 } }, world)
    local capsule = Node.new('Mesh3D', { position = { -40, 80, 0 }, size = { 20, 20, 20 } }, world)
    physics:addBody(sphere, { collider = { shape = 'Sphere', radius = 10 }, restitution = 0.5 })
    physics:addBody(
        capsule,
        { collider = { shape = 'Capsule', radius = 10, height = 20 }, rotationFactor = { 0, 0, 0 } }
    )
    for i = 1, 180 do
        physics:update(1 / 60)
    end
    test:check(
        sphere.position[2] > 9 and capsule.position[2] > 19,
        'Sphere and capsule collide with 3D ground'
    )
    local before = cube.position[2]
    physics:update(0)
    test:check(cube.position[2] == before, 'Zero scaled delta freezes the physics world')
    test:check(not pcall(function()
        body:set({ density = -1 })
    end), 'Invalid physical properties report explicit errors')
    physics:release()
    test:check(#physics.bodies == 0, 'Physics release removes all rigid bodies')
    world:destroy()
    parent:destroy()
    ui:release()
    resources:release()
end
