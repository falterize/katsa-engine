local Playground = {}

function Playground.create(state)
    local ui = state.scene.ui
    local function body(name, x, y, w, h, bodyType, shape)
        local item = ui:create('Body2D', {
            name = name,
            position = { x, -y },
            size = { w, h },
            bodyType = bodyType or 'Dynamic',
        })
        local collider = ui:create('Collider2D', {
            name = 'Collider',
            shape = shape or 'Box',
            size = { w, h },
        }, item)
        local visual = ui:create('Frame', {
            name = 'Visual',
            size = { 1, 0, 1, 0 },
            backgroundColor = { 70 / 255, 180 / 255, 230 / 255 },
        }, collider)
        if shape == 'Circle' then
            ui:create('UICorner', { radius = { 0.5, 0 } }, visual)
        end
        return item
    end
    body('Floor2D', 640, 660, 1160, 26, 'Static')
    body('LeftWall2D', 60, 430, 20, 460, 'Static')
    body('RightWall2D', 1220, 430, 20, 460, 'Static')
    local ramp = body('Ramp2D', 310, 545, 260, 18, 'Static')
    ramp.rotation = -12
    for i = 1, 18 do
        body('Crate2D_' .. i, 150 + i % 5 * 48, 170 - math.floor(i / 5) * 42, 34, 34)
    end
    for i = 1, 5 do
        body('Ball2D_' .. i, 490 + i * 42, 190 - i * 20, 30, 30, nil, 'Circle')
    end
    local function link(kind, name, x, length)
        local a = body(name .. 'Anchor', x, 210, 14, 14, 'Static')
        local b = body(name .. 'Weight', x + 45, 210 + length, 42, 42, nil, 'Circle')
        local p = ui:create('Attachment2D', { name = name .. 'Attachment0' }, a)
        local q = ui:create('Attachment2D', { name = name .. 'Attachment1' }, b)
        return ui:create(kind, {
            name = name,
            attachment0 = p,
            attachment1 = q,
            length = length,
            maxLength = length,
            frequency = 2,
            dampingRatio = 0.3,
        }),
            b
    end
    link('RopeConstraint2D', 'Rope2D', 800, 130)
    link('SpringConstraint2D', 'Spring2D', 960, 110)
    local anchor = body('HingeAnchor2D', 1080, 440, 12, 12, 'Static')
    local arm = body('MotorArm2D', 1080, 440, 150, 16)
    ui:create('HingeConstraint2D', {
        name = 'MotorHinge2D',
        attachment0 = ui:create('Attachment2D', {}, anchor),
        attachment1 = ui:create('Attachment2D', {}, arm),
        motorEnabled = true,
        motorSpeed = 75,
        motorForce = 200000,
    })
    local sensor = body('Trigger2D', 590, 592, 120, 90, 'Static')
    sensor.isTrigger = true
    local triggerVisual = sensor:findByType('Frame', true)
    triggerVisual.backgroundColor = { 1, 180 / 255, 70 / 255 }
    triggerVisual.backgroundTransparency = 0.65
    state.triggerCount = 0
    sensor:connect('triggerEnter', function()
        state.triggerCount = state.triggerCount + 1
        if state.triggerLabel then
            state.triggerLabel.text = 'Trigger entries: ' .. state.triggerCount
        end
    end)
    state.ball = body('ImpulseBall2D', 700, 540, 35, 35, nil, 'Circle')
    local custom = body('CustomPolygon2D', 430, 390, 60, 60)
    custom:findByType('Collider2D'):destroy()
    local polygon = ui:create('Collider2D', {
        shape = 'Polygon',
        size = { 60, 60 },
        points = {
            { -30, 30 },
            { 30, 30 },
            { 30, 10 },
            { -5, 10 },
            { -5, -30 },
            { -30, -30 },
        },
    }, custom)
    ui:create('ImageLabel', {
        name = 'PolygonVisual',
        image = 'scene://textures/polygon.png',
        size = { 1, 0, 1, 0 },
        backgroundTransparency = 1,
        imageColor = { 70 / 255, 180 / 255, 230 / 255 },
    }, polygon)
    local image = body('ImageCollider2D', 620, 430, 96, 96)
    image:findByType('Collider2D'):destroy()
    local mask = ui:create('Collider2D', {
        shape = 'Image',
        image = 'scene://textures/colliderMask.png',
        size = { 96, 96 },
        collisionLevel = 'Detailed',
        imageResolution = 128,
    }, image)
    ui:create('ImageLabel', {
        name = 'ImageVisual',
        image = 'scene://textures/colliderMask.png',
        size = { 1, 0, 1, 0 },
        backgroundTransparency = 1,
        imageColor = { 70 / 255, 180 / 255, 230 / 255 },
    }, mask)
end

return Playground
