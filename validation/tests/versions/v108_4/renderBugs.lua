-- Rendering regressions on the real renderer: the stripe seen when the camera nears the floor
-- and flicker of particles that cast/receive shadows. KATSA_CARS_SHOT=<dir> saves screenshots.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

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

function Tests:draw()
    self.frame = self.frame + 1
    local frame, host = self.frame, self.host
    if frame == 1 then
        host = open(self, 'shadows')
        host.camera.position = { 0, 0.6, -140 }
        host.camera.rotation = { -0.35, 0, 0 }
    end
    if host then
        host:update(1 / 60, 1 / 60)
        host:draw()
    end
    if frame == 40 then
        self:shot('floorLow')
    elseif frame == 41 then
        host:release()
        host = open(self, 'particles')
        local world = host.world
        world.environment.shadows.enabled = true
        for _, emitter in ipairs(host.demo.emitters or {}) do
            emitter.castShadow, emitter.receiveShadow = true, true
        end
    elseif frame == 80 then
        self:shot('particlesShadowA')
        local lit = 0
        for _, emitter in ipairs(host.world.particles.emitters) do
            if emitter.castShadow and emitter.receiveShadow and #emitter.particles > 0 then
                lit = lit + 1
            end
        end
        self:check(lit > 0, 'Shadow-casting receiving particle emitters render with live particles')
    elseif frame == 81 then
        self:shot('particlesShadowB')
    elseif frame == 90 then
        host:release()
        print('PASSED ' .. self.count .. ' v108.4 render checks')
        katsa.event.quit()
    end
end

return Tests
