local ipairs = require('source.engine.math.array').ipairs

-- Reuse existing stress objects/lights; toggles never change scene counts or quality.
local Motion = {}
Motion.__index = Motion

function Motion.new(scene)
    return setmetatable(
        { scene = scene, time = 0, cubeEnabled = false, lightsEnabled = false },
        Motion
    )
end

function Motion:toggleCube()
    self.cubeEnabled = not self.cubeEnabled
    if self.cubeEnabled then
        self.cube = self.scene.world.byName['Cube10.2']
        self.cubeY = self.cube.position.y
        self.cubeYaw = self.cube.rotation.y
        self.cubeStart = self.time
    end
    self.cubeButton.text = self.cubeEnabled and 'Cube motion: ON' or 'Cube motion: OFF'
end

function Motion:toggleLights()
    self.lightsEnabled = not self.lightsEnabled
    if self.lightsEnabled then
        self.lights = {}
        self.lightStart = self.time
        for i, light in ipairs(self.scene.world.lights) do
            self.lights[i] = {
                node = light,
                x = light.position.x,
                z = light.position.z,
                yaw = light.rotation and light.rotation.y,
            }
        end
    end
    self.lightButton.text = self.lightsEnabled and 'Light motion: ON' or 'Light motion: OFF'
end

function Motion:update3D(dt)
    if not self.cubeEnabled and not self.lightsEnabled then
        return
    end
    self.time = self.time + dt
    if self.cubeEnabled and not self.cube.destroyed then
        local t = self.time - self.cubeStart
        self.cube.position.y = self.cubeY + math.sin(t * 2) * 18
        self.cube.rotation.y = self.cubeYaw + t * 60
    end
    if self.lightsEnabled then
        local t = self.time - self.lightStart
        for i, entry in ipairs(self.lights) do
            local light = entry.node
            if not light.destroyed then
                -- Subtract the initial phase so enabling causes no position jump.
                light.position.x = entry.x + (math.sin(t * 2 + i) - math.sin(i)) * 16
                light.position.z = entry.z + (math.cos(t * 2 + i) - math.cos(i)) * 12
                if light.rotation then
                    light.rotation.y = entry.yaw + math.sin(t * 1.5) * 25
                end
            end
        end
    end
end

function Motion:buildUI()
    local ui = self.scene.ui
    self.panel = ui:container({
        name = 'StressMotionControls',
        _viewportAuthored = true,
        position = { 0, 10, 0, 104 },
        size = { 0, 320, 0, 30 },
        backgroundTransparency = 1,
        zIndex = 45,
    }, ui.content)
    self.cubeButton = ui:button({
        position = { 0, 0, 0, 0 },
        size = { 0.5, -4, 1, 0 },
        text = 'Cube motion: OFF',
        textScaled = true,
        maxTextSize = 15,
        onPress = function()
            self:toggleCube()
        end,
    }, self.panel)
    self.lightButton = ui:button({
        position = { 0.5, 4, 0, 0 },
        size = { 0.5, -4, 1, 0 },
        text = 'Light motion: OFF',
        textScaled = true,
        maxTextSize = 15,
        onPress = function()
            self:toggleLights()
        end,
    }, self.panel)
end

function Motion:resize()
    self.panel.size = { 0, math.min(320, self.scene.ui.width - 20), 0, 30 }
end

function Motion.create(state, scene)
    local self = Motion.new(scene)
    scene.stressMotion = self
    self:buildUI()
    return self
end

return Motion
