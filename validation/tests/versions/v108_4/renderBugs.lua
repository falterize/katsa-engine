-- Real-renderer regressions: depth-only shadow targets, normal-map seams and particle shadows.
-- KATSA_CARS_SHOT=<dir> saves screenshots (the files land in the virtual save directory).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    self.luma = {}
    return self
end

function Tests:update() end

-- Mean luminance (0..255) of the lower screen band, read from a captured frame.
local function floorLuma(image)
    local p, w, h = image:getPointer(), image:getWidth(), image:getHeight()
    local sum, n = 0, 0
    for y = math.floor(h * 0.4), math.floor(h * 0.95) - 1, 4 do
        for x = 0, w - 1, 4 do
            local i = (y * w + x) * 4
            sum = sum + (p[i] + p[i + 1] + p[i + 2]) / 3
            n = n + 1
        end
    end
    return sum / n
end

function Tests:measure(key)
    katsa.graphics.captureScreenshot(function(image)
        self.luma[key] = floorLuma(image)
    end)
end

function Tests:shot(name)
    local dir = os.getenv('KATSA_CARS_SHOT')
    if dir then
        katsa.graphics.captureScreenshot(dir .. '/' .. name .. '.png')
    end
end

local function open(self, id)
    local host = require('source.game.runtime.application').new(self.manager, id)
    host:load()
    self.host = host
    return host
end

local PHASE = 60

function Tests:draw()
    self.frame = self.frame + 1
    local phase = math.floor((self.frame - 1) / PHASE) + 1
    local step = (self.frame - 1) % PHASE + 1
    if phase > 2 then
        print('PASSED ' .. self.count .. ' v108.4 render checks')
        return katsa.event.quit()
    end
    if step == 1 then
        if self.host then
            self.host:release()
        end
        open(self, phase == 1 and 'graphicsLab' or 'particles')
        if phase == 2 then
            self.host.world.environment.shadows.enabled = true
            for _, emitter in ipairs(self.host.demo.emitters or {}) do
                emitter.castShadow, emitter.receiveShadow = true, true
            end
        end
    end
    local host = self.host
    host:update(1 / 60, 1 / 60)
    host:draw()
    if phase == 1 then
        local shadows = host.world.environment.shadows
        if step == 40 then
            self:measure('on')
            self:shot('graphicsLabShadowsOn')
        elseif step == 42 then
            shadows.enabled = false
        elseif step == 50 then
            self:measure('off')
            self:shot('graphicsLabShadowsOff')
        elseif step == 55 then
            -- The shadow pass renders into a depth-only canvas. When that target silently
            -- fell back to the screen, the atlas stayed empty and the whole floor was shadowed.
            local on, off = self.luma.on, self.luma.off
            self:check(on and off, 'graphicsLab frames were captured')
            self:check(
                on > off * 0.8,
                string.format('shadows do not darken the whole floor (%.1f vs %.1f lit)', on, off)
            )
        end
    elseif step == 40 then
        self:shot('particlesShadows')
        local lit = 0
        for _, emitter in ipairs(host.world.particles.emitters) do
            if emitter.castShadow and emitter.receiveShadow and #emitter.particles > 0 then
                lit = lit + 1
            end
        end
        self:check(lit > 0, 'Shadow-casting receiving particle emitters render with live particles')
    end
end

return Tests
