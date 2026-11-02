local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Theme = require('source.engine.ui.theme')

local Lab = {}
Lab.__index = Lab

function Lab.new(scene)
    local self = setmetatable({
        scene = scene,
        preset = 'Pixel',
        pixelSize = 24,
        noise = 0.08,
        scanlines = 0.15,
        distortion = 0.004,
    }, Lab)
    scene.world.environment.debug.gizmos.enabled = false
    scene.world.environment.sky.enabled = false
    local layers = scene.world.shaderLayers
    layers:add('Static', 10)
    layers:add('Pixel', 20)
    -- Pixel replaces the default 2D effects; neither CRT nor Pixel processes this scene's 3D render.
    layers:setInteracts('Pixel', 'Default2D', false)
    layers:setInteracts('Static', 'Default3D', false)
    layers:setInteracts('Pixel', 'Default3D', false)
    return self
end

function Lab:sync()
    self.pixel.enabled = self.preset == 'Pixel' or self.preset == 'Both'
    -- Transparency bypasses only the CRT effect without pausing its viewport descendants.
    self.tv.shaderTransparency = (self.preset == 'CRT' or self.preset == 'Both') and 0 or 1
    self.pixel.uniforms.pixelSize = self.pixelSize
    self.tv.uniforms.noiseStrength = self.noise
    self.tv.uniforms.scanlineStrength = self.scanlines
    self.tv.uniforms.distortion = self.distortion
    self.effectLabel.text = self.preset:upper() .. ' / ' .. self.pixelSize .. ' px'
    for _, preset in ipairs({ 'Clean', 'Pixel', 'CRT', 'Both' }) do
        self.buttons[preset].backgroundColor = self.preset == preset and Theme.accent
            or Theme.button
    end
    for key, text in pairs({
        Pixel = 'Pixel block: ' .. self.pixelSize .. ' px',
        Noise = string.format('CRT noise: %.2f', self.noise),
        Scan = string.format('Scanlines: %.2f', self.scanlines),
        Distortion = string.format('Horizontal jitter: %.3f', self.distortion),
    }) do
        self.sliders[key].label.text = text
    end
    self.buttons.Default3D.text = '3D tint: ' .. (self.default.enabled and 'ON' or 'OFF')
    self.buttons.Wave3D.text = '3D wave: ' .. (self.wave.enabled and 'ON' or 'OFF')
    self.buttons.Pixel3D.text = '3D pixel UV: ' .. (self.pixel3D.enabled and 'ON' or 'OFF')
end

function Lab:update(dt)
    self.scene.world:updateNodes(dt)
    local ui = self.scene.ui
    local narrow = ui.width < 680
    self.controls.size = narrow and { 0.42, -8, 1, -16 } or { 0, 238, 1, -16 }
    self.views.position = narrow and { 0.42, 8, 0, 8 } or { 0, 254, 0, 8 }
    self.views.size = narrow and { 0.58, -16, 1, -16 } or { 1, -262, 1, -16 }
    self.scene.ui:layout()
    local width, height = katsa.graphics.getDimensions()
    local x, y = self.pixel._x * ui.scale + ui.offsetX, self.pixel._y * ui.scale + ui.offsetY
    local w, h = self.pixel._width * ui.scale, self.pixel._height * ui.scale
    for _, effect in ipairs({ self.tv, self.pixel }) do
        effect.uniforms.resolution = { width, height }
        effect.uniforms.regionOrigin = { x, y }
        effect.uniforms.regionExtent = { w, h }
    end
end

return Lab
