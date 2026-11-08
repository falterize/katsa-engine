-- Diagnostic: is the main frame of windowsLab transparent where nothing is drawn?
-- Run: KATSA_SHOT=tmp/alpha xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.alpha
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    if self.host then
        self.host:update(1 / 60, 1 / 60)
        self.host:draw()
    end
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'windowsLab')
        self.host:load()
    elseif self.frame == 20 then
        local scene = self.host.scene or self.host.game or self.host.demo
        if not (scene and scene.world) then
            local keys = {}
            for k, v in pairs(self.host) do keys[#keys + 1] = k .. ':' .. type(v) end
            print('ALPHA host keys', table.concat(keys, ' '))
            scene = self.manager.stack[#self.manager.stack]
        end
        print('ALPHA activeCamera', tostring(scene.world and scene.world.activeCamera ~= nil), 'clearColor', scene.clearColor and scene.clearColor[4])
        local cam = scene.world.activeCamera
        print('ALPHA camera', cam and cam.className, cam and cam.name, cam and cam.parent and cam.parent.name, 'cameras', #scene.world.cameras)
        katsa.graphics.captureScreenshot((os.getenv('KATSA_SHOT') or 'tmp/alpha') .. '/lab.png')
    elseif self.frame == 24 then
        katsa.event.quit()
    end
end

return Tests
