local ipairs = require('source.engine.math.array').ipairs

local Debug = {}

function Debug.new(scene)
    local ui = scene.ui
    local overlay = ui:create('Frame', {
        position = { 0, 0, 0, 0 },
        size = { 0, 1280, 0, 720 },
        name = 'DebugMenu',

        capture = true,
        visible = false,
        backgroundColor = {
            0,
            0,
            0,
            0.7,
        },
    }, ui.overlays)
    local panel = ui:create('ScrollFrame', {
        position = { 0, 270, 0, 145 },
        size = { 0, 740, 0, 520 },

        length = 1700,
        backgroundColor = { 0.035, 0.075, 0.12 },
        backgroundTransparency = 1 - 1,
    }, overlay)
    local heading = ui:create('TextLabel', {
        position = { 0, 20, 0, 15 },
        size = { 0, 570, 0, 46 },

        text = 'DEBUG / RENDER / PHYSICS',
        fontSize = 28,
    }, panel)
    ui:create('Button', {
        position = { 0, 635, 0, 15 },
        size = { 0, 85, 0, 44 },

        text = 'Close',
        fontSize = 21,
        backgroundColor = { 0.2, 0.3, 0.4 },
        backgroundTransparency = 1 - 1,
        onPress = function()
            overlay.visible = false
        end,
    }, panel)
    local y = 80
    local section, sections = '2D Physics', {}
    local function register(node)
        sections[#sections + 1] = { node = node, section = section, row = y }
    end

    local function row(text, callback)
        local button = ui:create('Button', {
            position = { 0, 20, 0, y },
            size = { 0, 700, 0, 44 },

            text = text,
            fontSize = 21,
            backgroundColor = { 0.09, 0.18, 0.26 },
            backgroundTransparency = 1 - 1,
            onPress = callback,
        }, panel)
        register(button)
        y = y + 54
        return button
    end
    for _, setting in ipairs({ 'enabled', 'shapes', 'joints', 'centers', 'velocities', 'contacts' }) do
        local button = row('2D physics debug: ' .. setting, function(button)
            local physics = scene.ui.physics2D
            if physics then
                physics.debug[setting] = not physics.debug[setting]
                button.text = '2D physics '
                    .. setting
                    .. ': '
                    .. (physics.debug[setting] and 'ON' or 'OFF')
            else
                button.text = 'This World2D has no physics'
            end
        end)
        button._debug2DSetting = setting
    end
    row('Pause 2D physics', function(button)
        local physics = scene.ui.physics2D
        if physics then
            physics.paused = not physics.paused
            button.text = 'Paused: ' .. tostring(physics.paused)
        end
    end)
    row('Single 2D physics step', function()
        local physics = scene.ui.physics2D
        if physics then
            local paused = physics.paused
            physics.paused = false
            physics:update(physics.fixedDelta)
            physics.paused = paused
        end
    end)
    section = 'Directions'
    for _, dimension in ipairs({ '2D', '3D' }) do
        row(dimension .. ' orientation axes ON/OFF', function(button)
            local key = 'orientation' .. dimension
            scene.ui.debug = scene.ui.debug or {}
            local target = dimension == '2D' and scene.ui.debug or scene.world.debug
            target[key] = not target[key]
            if dimension == '2D' then
                scene.world.debug[key] = false
            end
            button.text = dimension .. ' orientation axes: ' .. (target[key] and 'ON' or 'OFF')
        end)
    end
    section = 'Diagnostics'
    row('CPU profiler / error journal', function()
        require('source.engine.editor.debug.diagnostics').open(scene.workspace)
    end)
    section = 'Rendering'
    scene.world.debug = scene.world.debug or { bones = false, wireframe = false }
    row('Bone debug ON/OFF', function(n)
        scene.world.debug.bones = not scene.world.debug.bones
        for _, animator in ipairs(scene.world.animators or {}) do
            animator.debugEnabled = scene.world.debug.bones
        end
        n.text = 'Bone debug: ' .. (scene.world.debug.bones and 'ON' or 'OFF')
    end)
    row('Wireframe render ON/OFF', function(n)
        scene.world.debug.wireframe = not scene.world.debug.wireframe
        n.text = 'Wireframe render: ' .. (scene.world.debug.wireframe and 'ON' or 'OFF')
    end)
    row('Free debug camera', function(n)
        local enabled = require('source.engine.cameras.debugCamera').toggle(scene)
        n.text = enabled and 'Free debug camera: ON' or 'Free debug camera: OFF'
    end)
    local physicsDebug = scene.world.environment.debug.physics
    local sliders = {}
    local debugSelected
    local getters = {
        ['3D density'] = function()
            return scene.world.environment.render.renderDensity
        end,
        ['Active lights'] = function()
            return scene.world.environment.lightSettings.maxActiveLights
        end,
        ['Mesh draw distance'] = function()
            return scene.camera.drawDistance
        end,
        ['Shadow strength'] = function()
            return scene.world.environment.shadows.strength
        end,
        ['Shadow update Hz'] = function()
            return scene.world.environment.shadows.updateHz
        end,
        ['Shadow distance'] = function()
            return scene.world.environment.shadows.distance
        end,
        ['Gravity Y'] = function()
            return scene.physics.gravity[2]
        end,
        ['Velocity iterations'] = function()
            return scene.physics.world:getNumVelocityIterations()
        end,
        ['Position iterations'] = function()
            return scene.physics.world:getNumPositionIterations()
        end,
    }

    local function slider(label, value, min, max, callback, getter)
        local text = ui:create('TextLabel', {
            position = { 0, 20, 0, y },
            size = { 0, 265, 0, 44 },
            text = string.format('%s %.2f', label, value),
            fontSize = 21,
            align = 'left',
        }, panel)
        local control = ui:create('Slider', {
            position = { 0, 290, 0, y },
            size = { 0, 420, 0, 44 },

            value = value,
            min = min,
            max = max,
            onChange = function(v)
                callback(v)
                text.text = string.format('%s %.2f', label, v)
            end,
        }, panel)
        register(text)
        register(control)
        sliders[#sliders + 1] = {
            control = control,
            label = text,
            title = label,
            get = getter
                or getters[label]
                or (
                    label:match('^Body3D ')
                    and function()
                        return debugSelected
                                and (debugSelected.settings[label:sub(8)] or debugSelected.object[label:sub(
                                    8
                                )])
                            or control.value
                    end
                ),
        }
        y = y + 54
    end
    row('Light gizmos ON/OFF', function()
        scene.world.lighting.debug.gizmos.enabled = not scene.world.lighting.debug.gizmos.enabled
    end)
    row('Light loop: ' .. scene.world.environment.render.lightLoop, function(button)
        local render = scene.world.environment.render
        render.lightLoop = render.lightLoop == 'Direct' and 'Masked' or 'Direct'
        button.text = 'Light loop: ' .. render.lightLoop
    end)
    row(
        'Static frame cache: ' .. (scene.world.environment.render.frameCache and 'ON' or 'OFF'),
        function(button)
            local render = scene.world.environment.render
            render.frameCache = not render.frameCache
            button.text = 'Static frame cache: ' .. (render.frameCache and 'ON' or 'OFF')
        end
    )
    slider('3D density', scene.world.environment.render.renderDensity, 0.5, 3, function(v)
        scene.world.environment.render.renderDensity = math.floor(v * 4 + 0.5) / 4
    end)
    slider('Active lights', scene.world.lighting.lightSettings.maxActiveLights, 0, 32, function(v)
        scene.world.lighting.lightSettings.maxActiveLights = math.floor(v)
    end)
    slider('Mesh draw distance', scene.camera.drawDistance, 50, 3000, function(v)
        scene.camera.drawDistance = v
    end)
    row('Camera3D layers: 1 / 2 / all', function()
        scene.camera.layers = scene.camera.layers == 1 and 2 or scene.camera.layers == 2 and -1 or 1
    end)
    local lighting = scene.world.lighting
    row('Shadows ON/OFF', function()
        lighting.shadows.enabled = not lighting.shadows.enabled
    end)
    row('Shadow map: 256 / 512 / 1024', function(n)
        local shadows = lighting.shadows
        shadows.resolution = shadows.resolution == 256 and 512
            or shadows.resolution == 512 and 1024
            or 256
        n.text = 'Shadow resolution: ' .. shadows.resolution
    end)
    row('Shadow filter: 1 / 4 / 9 taps', function(n)
        local shadows = lighting.shadows
        shadows.filterSamples = shadows.filterSamples == 1 and 4
            or shadows.filterSamples == 4 and 9
            or 1
        n.text = 'Shadow filter: ' .. shadows.filterSamples
    end)
    slider('Shadow strength', lighting.shadows.strength, 0, 1, function(v)
        lighting.shadows.strength = v
    end)
    slider('Shadow update Hz', lighting.shadows.updateHz, 1, 60, function(v)
        lighting.shadows.updateHz = v
    end)
    slider('Shadow distance', lighting.shadows.distance, 40, 600, function(v)
        lighting.shadows.distance = v
    end)
    section = '3D Physics'
    if scene.physics then
        local physics = scene.physics
        row('Physics debug ON/OFF', function()
            physicsDebug.enabled = not physicsDebug.enabled
        end)
        row('Pause physics ON/OFF', function()
            physics.paused = not physics.paused
        end)
        row('Single physics step', function()
            local paused = physics.paused
            physics.paused = false
            physics:update(physics.fixedDelta)
            physics.paused = paused
        end)
        for _, field in ipairs({
            'drawShapes',
            'drawAabbs',
            'drawBases',
            'drawContacts',
            'drawContactBases',
            'drawPairs',
            'drawJoints',
            'drawJointLimits',
            'drawBvh',
        }) do
            row(field .. ' ON/OFF', function()
                physicsDebug.enabled = true
                physicsDebug[field] = not physicsDebug[field]
            end)
        end
        slider('Gravity Y', physics.gravity[2], -400, 100, function(v)
            physics:setGravity(physics.gravity[1], v, physics.gravity[3])
        end)
        slider('Velocity iterations', physics.world:getNumVelocityIterations(), 1, 20, function(v)
            physics.world:setNumVelocityIterations(math.floor(v))
        end)
        slider('Position iterations', physics.world:getNumPositionIterations(), 1, 10, function(v)
            physics.world:setNumPositionIterations(math.floor(v))
        end)
        local selected
        local inspector = row('Pick body at screen center', function(n)
            scene.camera:update(love.graphics.getDimensions())
            local p, f = (scene.camera.worldPosition or scene.camera.position), scene.camera.forward
            local hit =
                physics:raycast(p, { p[1] + f[1] * 1000, p[2] + f[2] * 1000, p[3] + f[3] * 1000 })
            selected = hit and hit.body
            debugSelected = selected
            n.text = selected and ('Selected: ' .. selected.object.name)
                or 'No body at screen center'
        end)
        for _, field in ipairs({
            'density',
            'friction',
            'restitution',
            'linearDamping',
            'angularDamping',
            'gravityScale',
        }) do
            slider(
                'Body3D ' .. field,
                (field == 'density' or field == 'mass') and 1 or field == 'gravityScale' and 1 or 0,
                0,
                (field == 'density' or field == 'mass') and 10 or field == 'gravityScale' and 3 or 1,
                function(value)
                    if selected and (field ~= 'mass' or selected.type == 'Dynamic') then
                        if selected.object:isA('Body3D') then
                            selected.object[field] = value
                        end
                        selected:set({
                            [field] = (field == 'density' or field == 'mass')
                                    and math.max(0.01, value)
                                or value,
                        })
                    end
                end
            )
        end
        row('Selected collision ON/OFF', function()
            if selected then
                selected:set({ canCollide = not selected.canCollide })
            end
        end)
        row('Selected query ON/OFF', function()
            if selected then
                selected:set({ canQuery = not selected.canQuery })
            end
        end)
        row('Selected sleep / wake', function()
            if selected then
                if selected.raw:isSleeping() then
                    selected.raw:wakeUp()
                else
                    selected.raw:sleep()
                end
            end
        end)
        inspector._debugInspector = true
    else
        local unavailable = ui:create('TextLabel', {
            position = { 0, 20, 0, y },
            size = { 0, 700, 0, 75 },

            text = 'This scene has no physics world. Open Physics Lab, Collision Models or Night Player.',
            fontSize = 22,
        }, panel)
        register(unavailable)
        y = y + 90
    end
    panel.length = y + 20
    section = 'Rendering'
    for _, name in ipairs({ 'Low', 'Medium', 'High' }) do
        row('Quality: ' .. name, function()
            scene.world:setQualityProfile(name)
        end)
    end
    section = 'Diagnostics'
    row('Measure shadow build / sampling costs', function()
        scene.pendingShadowProbe = true
    end)
    panel.length = math.max(panel.length, y + 24)
    local tabs = {}
    function overlay:setDebugSection(selected)
        heading.text = 'Debug / ' .. selected
        for name, button in pairs(tabs) do
            button.backgroundColor = name == selected and { 0.12, 0.38, 0.5 } or { 0.07, 0.14, 0.2 }
        end
        local rows, nextY = {}, 80
        for _, item in ipairs(sections) do
            local node = item.node
            node.visible = item.section == selected
            if node.visible then
                if not rows[item.row] then
                    rows[item.row] = nextY
                    nextY = nextY + 54
                end
                node.position[4] = rows[item.row]
            end
        end
        panel.length, panel.scrollY = nextY + 24, 0
        ui:invalidate()
        self.debugSection = selected
    end
    for index, name in ipairs({
        '2D Physics',
        '3D Physics',
        'Rendering',
        'Directions',
        'Diagnostics',
    }) do
        tabs[name] = ui:button({
            name = 'DebugTab' .. index,
            position = { 0, 270 + (index - 1) * 148, 0, 95 },
            size = { 0, 144, 0, 42 },
            text = name,
            fontSize = 16,
            onPress = function()
                overlay:setDebugSection(name)
            end,
        }, overlay)
    end
    overlay:setDebugSection(scene.ui.physics2D and '2D Physics' or 'Rendering')
    overlay._syncDebug = function()
        for _, item in ipairs(sections) do
            local setting = item.node._debug2DSetting
            if setting then
                local physics = scene.ui.physics2D
                item.node.text = physics
                        and (setting .. ': ' .. (physics.debug[setting] and 'ON' or 'OFF'))
                    or 'No Physics2D in this World2D'
            end
        end
        for _, item in ipairs(sliders) do
            local value = item.get and item.get() or item.control.value
            item.control.value = value
            item.label.text = string.format('%s %.2f', item.title, value)
        end
    end
    overlay._syncDebug()
    return overlay
end

return Debug
