local unpack = require('../math.array').unpack
local ipairs = require('../math.array').ipairs
local M = require('../math.math3d')
local Geometry = require('../graphics.geometry.primitives')
local Validate = require('../core.validate')
local Node = require('../nodes')
local Cameras = {}

function Cameras.install(World3D)
    function World3D:addCamera(settings, parent)
        local camera = require('../cameras.camera').new(settings)
        camera._world = self
        camera.parent = parent or self.folders.Cameras
        self.cameras[#self.cameras + 1] = camera
        camera:onDestroy(function()
            for i, c in ipairs(self.cameras) do
                if c == camera then
                    table.remove(self.cameras, i)
                    break
                end
            end
            if self.activeCamera == camera then
                self.activeCamera = self.cameras[1]
            end
        end)
        self.activeCamera = self.activeCamera or camera
        return camera
    end

    function World3D:setCamera(camera, seconds)
        assert(
            camera:isA('Camera3D') and camera._world == self and not camera.destroyed,
            'Active camera must be a live Camera3D node'
        )
        local old = self.activeCamera
        if seconds and old and old ~= camera and camera._controller then
            camera._controller:update(0, true)
            local destination =
                { position = camera:getWorldPosition(), rotation = camera:getLookRotation() }
            camera._controller:transitionTo(destination.position, destination.rotation, seconds)
            camera._controller.transition.from = { unpack(old:getWorldPosition()) }
            camera._controller.transition.rotation = old:getLookRotation()
        end
        self.activeCamera = camera
        return camera
    end
end

return Cameras
