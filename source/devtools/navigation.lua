-- Legacy navigation of the example scenes: the header (Menu, Pause, Stats, Tools), the Tools
-- panel with the demonstration switches, the audio mixer and the demo shader effects. It is
-- driven by the runtime hooks only; scenes never call into it. With the editor module's ImGui
-- toolbar the header and the Tools panel stay hidden.
local ipairs = require('source.engine.math.array').ipairs

local Navigation = { name = 'navigation' }
Navigation.__index = Navigation

function Navigation.install(scene)
    return setmetatable({ scene = scene }, Navigation)
end

function Navigation:toggleMusic()
    local scene = self.scene
    if scene.musicVoice and not scene.musicVoice.released and not scene.musicVoice.manualPause then
        scene.musicVoice:pause()
    elseif scene.musicVoice and not scene.musicVoice.released then
        scene.musicVoice:resume()
    elseif katsa.filesystem.getInfo('assets/audio/music/demoMusic.wav', 'file') then
        scene.musicVoice = scene.audio:play(
            'assets/audio/music/demoMusic.wav',
            { group = 'music', stream = true, loop = true }
        )
    end
    self:syncButtons()
end


function Navigation:toggleBillboards()
    local scene = self.scene
    scene.billboardsVisible = not scene.billboardsVisible
    for _, board in ipairs(scene.world.billboards) do
        board.visible = scene.billboardsVisible
    end
    self:syncButtons()
end


function Navigation:syncButtons()
    local scene = self.scene
    if not scene.buttons then
        return
    end
    scene.buttons.music.text = scene.musicVoice
            and not scene.musicVoice.released
            and not scene.musicVoice.manualPause
            and 'Music: ON'
        or 'Music: OFF'
    scene.buttons.boards.text = scene.billboardsVisible and 'Billboards: ON' or 'Billboards: OFF'
    scene.buttons.motion.text = scene.billboardMotion and 'Motion: ON' or 'Motion: OFF'
    scene.buttons.time.text = 'Global time: ' .. scene.manager.time.scale .. 'x'
    scene.buttons.effects.text = scene.effectsEnabled and 'Shaders: ON' or 'Shaders: OFF'
end

-- Spreads the visible primary header buttons evenly over the left 80 % of the bar (the right
-- 20 % belongs to the Workspace tab), so hiding one (Tools with ImGui) leaves no gap.

function Navigation:layoutNavigation()
    local scene = self.scene
    local list = {}
    local primary = { scene.buttons.menu, scene.buttons.pause, scene.buttons.stats, scene.toolsButton }
    for _, node in ipairs(primary) do
        if node and node.visible then
            list[#list + 1] = node
        end
    end
    local width = 0.8 / math.max(#list, 1)
    for i, node in ipairs(list) do
        node.position = { (i - 1) * width, 8, 0, 6 }
        node.size = { width, -12, 0, 42 }
    end
end


function Navigation:buildMixer()
    local scene = self.scene
    local ui = scene._ui
    scene.mixerOverlay = ui:container({
        _viewportAuthored = true,
        name = 'AudioMixer',
        size = { 1, 0, 1, 0 },
        capture = true,
        visible = false,
        backgroundColor = { 0, 0, 0 },
        backgroundTransparency = 0.4,
    }, ui.overlays)
    scene.mixerPanel = ui:container({
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 480, 0, 380 },
        anchorPoint = { 0.5, 0.5 },
        capture = true,
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, scene.mixerOverlay)
    ui:text({
        position = { 0, 14, 0, 8 },
        size = { 1, -112, 0, 36 },
        text = 'Audio mixer',
        fontSize = 22,
        align = 'left',
    }, scene.mixerPanel)
    do
        local node = ui:button({
            position = { 1, -10, 0, 8 },
            size = { 0, 80, 0, 36 },
            anchorPoint = { 1, 0 },
            text = 'Close',
            fontSize = 16,
            backgroundColor = { 0.085, 0.135, 0.19 },
        }, scene.mixerPanel)
        node:connect('press', function()
            scene.mixerOverlay.visible = false
        end)
    end
    local body = ui:scroll(
        { position = { 0, 12, 0, 54 }, size = { 1, -24, 1, -66 }, length = 304 },
        scene.mixerPanel
    )
    scene.groupSliders = {}
    for i, name in ipairs({ 'master', 'music', 'effects', 'ui' }) do
        local y = (i - 1) * 56
        local label = ui:text({
            position = { 0, 4, 0, y },
            size = { 0.35, -8, 0, 44 },
            text = name:upper(),
            fontSize = 15,
            align = 'left',
        }, body)
        scene.groupSliders[name] = ui:slider({
            position = { 0.35, 0, 0, y },
            size = { 0.65, -8, 0, 44 },
            value = scene.audio:getGroupVolume(name),
        }, body)
        scene.groupSliders[name]:connect('changed', function(value)
            scene.audio:setGroupVolume(name, value)
            label.text = name:upper() .. ' ' .. math.floor(value * 100 + 0.5) .. '%'
            scene.audio:update(scene.camera)
        end)
    end
    ui:text({
        position = { 0, 4, 0, 232 },
        size = { 1, -8, 0, 64 },
        text = 'Master multiplies every group. UI audio continues when game time is paused.',
        fontSize = 15,
        align = 'left',
    }, body)
end


function Navigation:playSound()
    local scene = self.scene
    scene.audio:play('assets/audio/effects/stereoChime.wav', {
        object = scene.world.byName['1']
            or scene.model and scene.model.objects[1]
            or scene.world.objects[1],
        volume = 0.9,
        minDistance = 30,
        maxDistance = 220,
        stereoWidth = 6,
    })
end



function Navigation:build()
    local scene = self.scene
    scene.buttons = {}
    local ui = scene._ui
    local header = ui:container({
        _viewportAuthored = true,
        name = 'Navigation',
        zIndex = 80,
        visible = not scene.settings.presentation or scene.settings.presentation.navigation ~= false,
        size = { 1, 0, 0, 54 },
        backgroundColor = { 0.025, 0.045, 0.075 },
        backgroundTransparency = 0.08,
    }, ui.content)
    scene.navigation = header
    scene.toolsPanel = ui:scroll({
        _viewportAuthored = true,
        name = 'Tools',
        position = { 0, 10, 0, 62 },
        size = { 0.65, 0, 1, -138 },
        length = 620,
        visible = false,
        backgroundColor = { 0.035, 0.07, 0.11 },
        zIndex = 40,
    }, ui.content)
    local row = 0

    local function button(name, text, x, y, width, callback)
        local primary = name == 'menu' or name == 'pause' or name == 'stats'
        local slot = ({ menu = 0, pause = 1, stats = 2 })[name]
        local settings = {
            position = primary and { slot * 0.2, 8, 0, 6 } or { 0, 10, 0, row * 44 + 8 },
            size = primary and { 0.2, -12, 0, 42 } or { 1, -20, 0, 38 },
            backgroundColor = { 0.08, 0.15, 0.22 },
            radius = 7,
            text = text,
            textScaled = true,
            maxTextSize = 18,
        }
        local node = ui:button(settings, primary and header or scene.toolsPanel)
        node:connect('press', function()
            scene.audio:play('assets/audio/effects/click.wav', { group = 'ui', timeScaled = false })
            callback()
        end)
        if not primary then
            row = row + 1
        end
        scene.buttons[name] = node
        return x + width + 10
    end
    do
        local node = ui:button({
            position = { 0.6, 8, 0, 6 },
            size = { 0.2, -12, 0, 42 },
            text = 'Tools',
            textScaled = true,
            maxTextSize = 18,
            backgroundColor = { 0.1, 0.25, 0.34 },
            radius = 7,
        }, header)
        scene.toolsButton = node
        node:connect('press', function()
            scene.toolsPanel.visible = not scene.toolsPanel.visible
        end)
    end
    local x = 16
    x = button('menu', 'Menu', x, 16, 85, function()
        scene.manager:switch(require('source.runtime.menu').new)
    end)
    x = button('pause', 'Pause', x, 16, 90, function()
        scene.pauseMenu:toggle()
    end)
    x = button('animations', 'Animations', x, 16, 145, function()
        scene.demoAnimations = not scene.demoAnimations
    end)
    x = button('fog', 'Fog', x, 16, 95, function()
        scene.world.environment.fog.enabled = not scene.world.environment.fog.enabled
    end)
    x = button('stats', 'Stats', x, 16, 95, function()
        scene.showStats = not scene.showStats
    end)
    x = button('sound', 'Sound', x, 16, 115, function()
        self:playSound()
    end)
    x = button('music', 'Music', x, 16, 145, function()
        self:toggleMusic()
    end)
    button('boards', 'Billboards', x, 16, 210, function()
        self:toggleBillboards()
    end)
    x = 16
    x = button('lights', '12 / 32 lights', x, 78, 170, function()
        local settings = scene.world.environment.lightSettings
        settings.maxActiveLights = settings.maxActiveLights == 12 and 32 or 12
    end)
    x = button('reset', 'Reset view', x, 78, 160, function()
        scene.camera.position = { 0, 0, 0 }
        scene.camera.rotation = { 0, 0, 0 }
    end)
    x = button('motion', 'Motion', x, 78, 170, function()
        scene.billboardMotion = not scene.billboardMotion
        self:syncButtons()
    end)
    x = button('mixer', 'Mixer', x, 78, 140, function()
        scene.mixerOverlay.visible = not scene.mixerOverlay.visible
    end)
    x = button('time', 'time', x, 78, 140, function()
        local scale = scene.manager.time.scale
        scene.manager.time:setScale(scale == 1 and 0.5 or scale == 0.5 and 0 or 1)
        scene.audio:update(scene.camera)
        self:syncButtons()
    end)
    button('effects', 'Shaders', x, 78, 175, function()
        scene.effectsEnabled = not scene.effectsEnabled
        if scene.objectEffect then
            scene.objectEffect.enabled = scene.effectsEnabled
        end
        scene.uiEffect.enabled = scene.effectsEnabled
        self:syncButtons()
    end)
    scene.uiEffect = scene._ui:create('Shader2D', {
        name = 'UIPulse',
        position = { 0, 0, 0, 54 },
        size = { 1, 0, 1, -54 },
        zIndex = 40,
        enabled = false,
        backgroundTransparency = 1,
        shaderPath = 'source/runtime/game/shaders/uiPulse.glsl',
        uniforms = { accent = { 0.25, 0.85, 1 } },
    }, scene._ui.content)
    scene.toolsPanel.length = row * 44 + 16
    self:buildMixer()
    self:syncButtons()
end

-- The demonstration shader effects the Shaders button switches (off at start).
function Navigation:buildEffects()
    local scene = self.scene
    scene.effectTarget = scene.world.byName['1']
        or scene.model and scene.model.objects[1]
        or scene.world.objects[2]
    if scene.effectTarget then
        scene.objectEffect = scene.world:create('Shader3D', {
            name = 'Wave3D',
            shaderPath = 'source/runtime/game/shaders/wave3D.glsl',
            enabled = false,
            animated = true,
            uniforms = { waveAmplitude = 0.12, glowColor = { 0.1, 0.7, 1 } },
        }, scene.effectTarget)
    end
end

-- The header and the Tools panel follow the presentation (hidden while a scene captures the
-- pointer) and stay hidden once the ImGui toolbar replaces them.
function Navigation:applyVisibility()
    local scene = self.scene
    local shown = not self.hidden and not self.replaced
    scene.navigation.visible = shown
    scene.toolsPanel.visible = shown and scene.toolsPanel.visible
    if self.hidden then
        scene.mixerOverlay.visible = false
    end
end

-- Hooks ---------------------------------------------------------------------------------------

function Navigation:presentation()
    local scene = self.scene
    self.hidden = scene.settings.presentation and scene.settings.presentation.navigation == false
    self:buildEffects()
    self:build()
    self:applyVisibility()
end

-- The editor's ImGui toolbar took over: the old header and the Tools panel are not shown again.
function Navigation:imguiAttached()
    self.replaced = true
    self.scene.toolsPanel.visible = false
    self.scene.toolsButton.visible = false
    self:applyVisibility()
end

-- A scene that captures the pointer (first person) hides the navigation while it plays.
function Navigation:immersion(captured)
    self.hidden = captured
    self:applyVisibility()
end

function Navigation:resize()
    local scene = self.scene
    if scene.mixerPanel then
        scene.mixerPanel.size =
            { 0, math.min(480, scene._ui.width - 24), 0, math.min(380, scene._ui.height - 24) }
    end
    if scene.toolsPanel then
        scene.toolsPanel.size = { 0, math.min(320, scene._ui.width - 24), 1, -138 }
    end
end

function Navigation:update()
    self:syncButtons()
end

return Navigation
