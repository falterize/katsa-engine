local Interface = {}

function Interface.create(state)
    local scene, physics = state.scene, state.physics
    local ui = scene.ui
    ui:text({
        name = 'Title',
        position = { 0, 24, 0, 60 },
        size = { 1, -48, 0, 36 },
        text = scene.settings.title .. ' | Box2D | F3: Stats',
        fontSize = 25,
    }, ui.content)
    state.triggerLabel = ui:text({
        position = { 0, 24, 0, 112 },
        size = { 0, 300, 0, 28 },
        text = 'Trigger entries: 0',
        fontSize = 18,
    }, ui.content)
    local panel = ui:scroll({
        name = 'PhysicsControls',
        position = { 0, 12, 0, 155 },
        size = { 0, 250, 0, 280 },
        length = 600,
        visible = false,
        backgroundColor = { 0.06, 0.12, 0.18 },
        zIndex = 20,
    }, ui.content)
    state.controlsPanel = panel
    require('source.engine.ui.widgets.collapsible').create(scene, panel, 'Physics / controls')
    local y = 8
    local function button(text, callback)
        do
            local node = ui:button({
                position = { 0, 8, 0, y },
                size = { 1, -16, 0, 35 },
                text = text,
                fontSize = 15,
            }, panel)
            if callback then
                node:connect('press', callback)
            end
        end
        y = y + 42
        panel.length = y + 8
    end
    button('Pause 2D', function(n)
        physics.paused = not physics.paused
        n.text = physics.paused and 'Resume 2D' or 'Pause 2D'
    end)
    button('Impulse', function()
        state.ball.body:applyImpulse(0, 1200)
    end)
    for _, name in ipairs({ 'enabled', 'shapes', 'joints', 'centers', 'contacts', 'velocities' }) do
        button('Debug: ' .. name, function()
            physics.debug[name] = not physics.debug[name]
        end)
    end
    button('2D time', function(n)
        ui.timeScale = ui.timeScale == 1 and 0.25 or ui.timeScale == 0.25 and 0 or 1
        n.text = '2D time: ' .. ui.timeScale .. 'x'
    end)
    button('3D time', function(n)
        local root = scene.world.root
        root.timeScale = root.timeScale == 1 and 0.25 or root.timeScale == 0.25 and 0 or 1
        n.text = '3D time: ' .. root.timeScale .. 'x'
    end)
    button('FOV +', function()
        ui.currentCamera.fov = math.min(150, ui.currentCamera.fov + 10)
    end)
    button('FOV -', function()
        ui.currentCamera.fov = math.max(20, ui.currentCamera.fov - 10)
    end)
    if not scene.navigation and scene.manager.sceneFactory and scene.manager.startScene then
        button('Main scene', function()
            scene.manager:requestSwitch(scene.manager.sceneFactory, scene.manager.startScene)
        end)
    end
end

return Interface
