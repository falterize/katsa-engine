local ipairs = require('source.engine.math.array').ipairs
local Models = require('source.engine.import.models')

local Methods = {}

function Methods:setNavigationVisible(visible)
    self.navigation.visible = visible
    if self.debugButton then
        self.debugButton.visible = visible
    end
    if self.workspace then
        self.workspace.tab.visible = visible
        if not visible then
            self.workspace:toggle(false)
        end
    end
    if not visible then
        self.showStats = false
        self.toolsPanel.visible = false
        self.mixerOverlay.visible = false
        if self.debugOverlay then
            self.debugOverlay.visible = false
        end
    end
end

function Methods:toggleMusic()
    if self.musicVoice and not self.musicVoice.released and not self.musicVoice.manualPause then
        self.musicVoice:pause()
    elseif self.musicVoice and not self.musicVoice.released then
        self.musicVoice:resume()
    else
        self.musicVoice = self.audio:play(
            'assets/audio/music/demoMusic.wav',
            { group = 'music', stream = true, loop = true }
        )
    end
    self:syncButtons()
end

function Methods:toggleBillboards()
    self.billboardsVisible = not self.billboardsVisible
    for _, board in ipairs(self.world.billboards) do
        board.visible = self.billboardsVisible
    end
    self:syncButtons()
end

function Methods:syncButtons()
    if self.cameraButtons then
        for _, node in ipairs(self.cameraButtons) do
            node.visible = self.world.activeCamera ~= nil and node._cameraControlEligible
        end
    end
    if not self.buttons then
        return
    end
    self.buttons.music.text = self.musicVoice
            and not self.musicVoice.released
            and not self.musicVoice.manualPause
            and 'Music: ON'
        or 'Music: OFF'
    self.buttons.boards.text = self.billboardsVisible and 'Billboards: ON' or 'Billboards: OFF'
    self.buttons.motion.text = self.billboardMotion and 'Motion: ON' or 'Motion: OFF'
    self.buttons.time.text = 'Global time: ' .. self.manager.time.scale .. 'x'
    self.buttons.effects.text = self.effectsEnabled and 'Shaders: ON' or 'Shaders: OFF'
end

function Methods:buildUI()
    self.buttons = {}
    local ui = self.ui
    local header = ui:container({
        _viewportAuthored = true,
        name = 'Navigation',
        zIndex = 80,
        visible = not self.settings.presentation or self.settings.presentation.navigation ~= false,
        size = { 1, 0, 0, 54 },
        backgroundColor = { 0.025, 0.045, 0.075 },
        backgroundTransparency = 0.08,
    }, ui.content)
    self.navigation = header
    self.toolsPanel = ui:scroll({
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
            onPress = function()
                self.audio:play(
                    'assets/audio/effects/click.wav',
                    { group = 'ui', timeScaled = false }
                )
                callback()
            end,
        }
        local node = ui:button(settings, primary and header or self.toolsPanel)
        if not primary then
            row = row + 1
        end
        self.buttons[name] = node
        return x + width + 10
    end
    ui:button({
        position = { 0.6, 8, 0, 6 },
        size = { 0.2, -12, 0, 42 },
        text = 'Tools',
        textScaled = true,
        maxTextSize = 18,
        backgroundColor = { 0.1, 0.25, 0.34 },
        radius = 7,
        onPress = function()
            self.toolsPanel.visible = not self.toolsPanel.visible
        end,
    }, header)
    local x = 16
    x = button('menu', 'Menu', x, 16, 85, function()
        self.manager:switch(require('source.game.runtime.menu').new)
    end)
    x = button('pause', 'Pause', x, 16, 90, function()
        self.pauseMenu:toggle()
    end)
    x = button('animations', 'Animations', x, 16, 145, function()
        self.demoAnimations = not self.demoAnimations
    end)
    x = button('fog', 'Fog', x, 16, 95, function()
        self.world.environment.fog.enabled = not self.world.environment.fog.enabled
    end)
    x = button('stats', 'Stats', x, 16, 95, function()
        self.showStats = not self.showStats
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
        local settings = self.world.environment.lightSettings
        settings.maxActiveLights = settings.maxActiveLights == 12 and 32 or 12
    end)
    x = button('reset', 'Reset view', x, 78, 160, function()
        self.camera.position = { 0, 0, 0 }
        self.camera.rotation = { 0, 0, 0 }
    end)
    x = button('motion', 'Motion', x, 78, 170, function()
        self.billboardMotion = not self.billboardMotion
        self:syncButtons()
    end)
    x = button('mixer', 'Mixer', x, 78, 140, function()
        self.mixerOverlay.visible = not self.mixerOverlay.visible
    end)
    x = button('time', 'time', x, 78, 140, function()
        local scale = self.manager.time.scale
        self.manager.time:setScale(scale == 1 and 0.5 or scale == 0.5 and 0 or 1)
        self.audio:update(self.camera)
        self:syncButtons()
    end)
    button('effects', 'Shaders', x, 78, 175, function()
        self.effectsEnabled = not self.effectsEnabled
        if self.objectEffect then
            self.objectEffect.enabled = self.effectsEnabled
        end
        self.uiEffect.enabled = self.effectsEnabled
        self:syncButtons()
    end)
    self.uiEffect = self.ui:create('Shader2D', {
        name = 'UIPulse',
        position = { 0, 0, 0, 54 },
        size = { 1, 0, 1, -54 },
        zIndex = 40,
        enabled = false,
        backgroundTransparency = 1,
        shaderPath = 'assets/shaders/examples/uiPulse.glsl',
        uniforms = { accent = { 0.25, 0.85, 1 } },
    }, self.ui.content)
    self.cameraButtons = {}
    for i, label in ipairs({ 'UP', 'DOWN' }) do
        local node = self.ui:button({
            position = { 0, 1120, 0, 490 + (i - 1) * 80 },
            size = { 0, 130, 0, 62 },

            backgroundColor = { 0.1, 0.2, 0.3 },
            backgroundTransparency = 1 - 0.8,
            text = label,
            visible = not self.character
                and self.settings.cameraButtons ~= false
                and self.zone ~= 'uiGallery'
                and self.zone ~= 'audioNodes'
                and self.zone ~= 'surfaceGallery',
            fontSize = 24,
            onPress = function()
                if i == 1 then
                    self.input.up = 1
                else
                    self.input.down = 1
                end
            end,
            onRelease = function()
                if i == 1 then
                    self.input.up = 0
                else
                    self.input.down = 0
                end
            end,
        }, self.ui.content)
        node._cameraControlEligible = node.visible
        node.visible = node.visible and self.world.activeCamera ~= nil
        self.cameraButtons[#self.cameraButtons + 1] = node
        node.onCancel = node.onRelease
    end
    self.statsLayer = ui:canvasGroup({
        name = 'StatsOverlay',
        size = { 1, 0, 1, 0 },
        zIndex = 100000,
        visible = false,
    })
    self.statistics = require('source.game.ui.statistics').new(self, self.statsLayer)
    self.statsScroll, self.statsPanel = self.statistics.panel.scroll, self.statistics.panel.header
    self.toolsPanel.length = row * 44 + 16
    self:buildMixer()
    self:syncButtons()
end

function Methods:buildMixer()
    local ui = self.ui
    self.mixerOverlay = ui:container({
        _viewportAuthored = true,
        name = 'AudioMixer',
        size = { 1, 0, 1, 0 },
        capture = true,
        visible = false,
        backgroundColor = { 0, 0, 0 },
        backgroundTransparency = 0.4,
    }, ui.overlays)
    self.mixerPanel = ui:container({
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 480, 0, 380 },
        anchorPoint = { 0.5, 0.5 },
        capture = true,
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, self.mixerOverlay)
    ui:text({
        position = { 0, 14, 0, 8 },
        size = { 1, -112, 0, 36 },
        text = 'Audio mixer',
        fontSize = 22,
        align = 'left',
    }, self.mixerPanel)
    ui:button({
        position = { 1, -10, 0, 8 },
        size = { 0, 80, 0, 36 },
        anchorPoint = { 1, 0 },
        text = 'Close',
        fontSize = 16,
        backgroundColor = { 0.085, 0.135, 0.19 },
        onPress = function()
            self.mixerOverlay.visible = false
        end,
    }, self.mixerPanel)
    local body = ui:scroll(
        { position = { 0, 12, 0, 54 }, size = { 1, -24, 1, -66 }, length = 304 },
        self.mixerPanel
    )
    self.groupSliders = {}
    for i, name in ipairs({ 'master', 'music', 'effects', 'ui' }) do
        local y = (i - 1) * 56
        local label = ui:text({
            position = { 0, 4, 0, y },
            size = { 0.35, -8, 0, 44 },
            text = name:upper(),
            fontSize = 15,
            align = 'left',
        }, body)
        self.groupSliders[name] = ui:slider({
            position = { 0.35, 0, 0, y },
            size = { 0.65, -8, 0, 44 },
            value = self.audio:getGroupVolume(name),
            onChange = function(value)
                self.audio:setGroupVolume(name, value)
                label.text = name:upper() .. ' ' .. math.floor(value * 100 + 0.5) .. '%'
                self.audio:update(self.camera)
            end,
        }, body)
    end
    ui:text({
        position = { 0, 4, 0, 232 },
        size = { 1, -8, 0, 64 },
        text = 'Master multiplies every group. UI audio continues when game time is paused.',
        fontSize = 15,
        align = 'left',
    }, body)
end

function Methods:playSound()
    self.audio:play('assets/audio/effects/stereoChime.wav', {
        object = self.world.byName['1']
            or self.model and self.model.objects[1]
            or self.world.objects[1],
        volume = 0.9,
        minDistance = 30,
        maxDistance = 220,
        stereoWidth = 6,
    })
end

return Methods
