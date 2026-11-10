local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Theme = require('source.engine.ui.theme')
local Preview = require('./previews.shader')

local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    self.root = ui:container({
        _viewportAuthored = true,
        name = 'ShaderShowcase',
        position = { 0, 12, 0, 112 },
        size = { 1, -24, 1, -128 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, self.root)
    self.controls = ui:scroll({
        name = 'ShaderControls',
        position = { 0, 8, 0, 8 },
        size = { 0, 238, 1, -16 },
        automaticLength = true,
        contentPadding = 12,
    }, self.root)
    self.views = ui:container({
        name = 'ShaderComparison',
        position = { 0, 254, 0, 8 },
        size = { 1, -262, 1, -16 },
        backgroundTransparency = 1,
    }, self.root)
    self.header = ui:text({
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 0, 30 },
        text = 'Same scene: original / processed',
        textScaled = true,
        maxTextSize = 18,
    }, self.views)
    self.clean = ui:create('ViewportFrame', {
        name = 'Original',
        position = { 0, 0, 0, 64 },
        size = { 0.5, -6, 1, -96 },
        canvasSize = {
            1,
            0,
            1,
            0,
        },
    }, self.views)
    self.tv = ui:create('Shader2D', {
        name = 'CRT',
        position = { 0.5, 6, 0, 64 },
        size = { 0.5, -6, 1, -96 },
        zIndex = 10,
        shaderLayer = 'Static',
        shaderPath = 'assets/shaders/examples/tvStatic.glsl',
        backgroundTransparency = 1,
        uniforms = {
            resolution = { 960, 540 },
            regionOrigin = { 0, 0 },
            regionExtent = { 1, 1 },
            noiseStrength = self.noise,
            scanlineStrength = self.scanlines,
            distortion = self.distortion,
        },
    }, self.views)
    self.viewport = ui:create(
        'ViewportFrame',
        { name = 'ProcessedViewport', size = { 1, 0, 1, 0 }, canvasSize = { 1, 0, 1, 0 } },
        self.tv
    )
    self.pixel = ui:create('Shader2D', {
        name = 'Pixel',
        position = { 0.5, 6, 0, 64 },
        size = { 0.5, -6, 1, -96 },
        zIndex = 11,
        shaderLayer = 'Pixel',
        shaderPath = 'assets/shaders/examples/pixelScreen.glsl',
        backgroundTransparency = 1,
        uniforms = {
            resolution = { 960, 540 },
            regionOrigin = { 0, 0 },
            regionExtent = { 1, 1 },
            pixelSize = self.pixelSize,
        },
    }, self.views)
    self.original = Preview.create(scene, self.clean, 'OriginalWorld')
    self.preview, self.cube = Preview.create(scene, self.viewport, 'ProcessedWorld')
    self.previewCube = self.cube
    local world = self.preview._world
    world.shaderLayers:add('Static', 10)
    world.shaderLayers:add('Pixel', 20)
    world.shaderLayers:setInteracts('Pixel', 'Default3D', false)
    self.default = world:create('Shader3D', {
        name = 'DefaultTint',
        shaderPath = 'assets/shaders/examples/tint3D.glsl',
        enabled = false,
        uniforms = { tintEffect = { 0.6, 0.8, 1 } },
    })
    self.wave = world:create('Shader3D', {
        name = 'Wave',
        shaderLayer = 'Static',
        shaderPath = 'assets/shaders/examples/wave3D.glsl',
        enabled = false,
        animated = true,
        uniforms = { waveAmplitude = 0.08, glowColor = { 1, 0.35, 0.08 } },
    })
    self.pixel3D = world:create('Shader3D', {
        name = 'PixelUV',
        shaderLayer = 'Pixel',
        shaderPath = 'assets/shaders/examples/pixel3D.glsl',
        enabled = false,
        uniforms = { pixelCells = { 8, 8 } },
    })
    ui:text({
        position = { 0, 0, 0, 34 },
        size = { 0.5, -6, 0, 26 },
        text = 'ORIGINAL',
        fontSize = 13,
        textColor = {
            0.55,
            0.85,
            1,
        },
    }, self.views)
    self.effectLabel = ui:text({
        position = { 0.5, 6, 0, 34 },
        size = { 0.5, -6, 0, 26 },
        text = 'PIXEL / 24 px',
        fontSize = 13,
        textColor = { 1, 0.8, 0.3 },
    }, self.views)
    self.status = ui:text({
        position = { 0, 0, 1, -28 },
        size = { 1, 0, 0, 26 },
        text = 'Compare the color bars, lettering and brick pattern.',
        fontSize = 12,
    }, self.views)
    local y = 0
    self.buttons = {}
    self.sliders = {}

    local function button(key, text, callback)
        local node = ui:button({
            position = { 0, 0, 0, y },
            size = { 1, 0, 0, 34 },
            text = text,
            fontSize = 13,
            backgroundColor = Theme.button,
            radius = Theme.corner,
        }, self.controls)
        node:connect('press', function()
            callback()
            self:sync()
        end)
        self.buttons[key] = node
        y = y + 40
        return node
    end
    ui:text(
        { size = { 1, 0, 0, 26 }, text = '2D screen effects', fontSize = 15, align = 'left' },
        self.controls
    )
    y = 32
    for _, preset in ipairs({ 'Clean', 'Pixel', 'CRT', 'Both' }) do
        button(preset, preset, function()
            self.preset = preset
        end)
    end

    local function slider(key, text, min, max, value, callback)
        local label = ui:text({
            position = { 0, 0, 0, y },
            size = { 1, 0, 0, 22 },
            text = text,
            fontSize = 12,
            align = 'left',
        }, self.controls)
        y = y + 24
        local node = ui:slider({
            position = { 0, 0, 0, y },
            size = { 1, 0, 0, 30 },
            min = min,
            max = max,
            value = value,
        }, self.controls)
        node:connect('changed', function(v)
            callback(v)
            self:sync()
        end)
        self.sliders[key] = { node = node, label = label }
        y = y + 38
    end
    slider('Pixel', 'Pixel block', 4, 48, self.pixelSize, function(v)
        self.pixelSize = math.floor(v + 0.5)
    end)
    slider('Noise', 'CRT noise', 0, 0.4, self.noise, function(v)
        self.noise = v
    end)
    slider('Scan', 'Scanlines', 0, 0.7, self.scanlines, function(v)
        self.scanlines = v
    end)
    slider('Distortion', 'Horizontal jitter', 0, 0.035, self.distortion, function(v)
        self.distortion = v
    end)
    button('Default3D', '3D tint: OFF', function()
        self.default.enabled = not self.default.enabled
    end)
    button('Wave3D', '3D wave: OFF', function()
        self.wave.enabled = not self.wave.enabled
    end)
    button('Pixel3D', '3D pixel UV: OFF', function()
        self.pixel3D.enabled = not self.pixel3D.enabled
    end)
    button('Layers', 'Shader layer matrix', function()
        scene.workspace.selected = self.pixel
        require('source.engine.editor.panels.shaderLayers').open(scene.workspace)
    end)
    button('Inspect', 'Inspect processed world', function()
        scene.workspace:toggle(true)
        scene.workspace:select(self.preview)
    end)
    button('Pause', 'Pause / resume both views', function()
        local scale = self.preview.timeScale == 0 and 1 or 0
        self.preview.timeScale = scale
        self.original.timeScale = scale
    end)
    self:sync()
end

return Interface
