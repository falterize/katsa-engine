local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    require('validation.tests.versions.v108_7.inspector').run(self)
    require('validation.tests.versions.v108_7.inputMap').run(self)
    require('validation.tests.versions.v108_7.attributes').run(self)
    require('validation.tests.versions.v108_7.lines').run(self)
    require('validation.tests.versions.v108_7.explorerOrder').run(self)
    require('validation.tests.versions.v108_7.curveRange').run(self)
    require('validation.tests.versions.v108_7.rampTimeline').run(self)
    require('validation.tests.versions.v108_7.blendShapes').run(self)
    require('validation.tests.versions.v108_7.pathDebug').run(self)
    require('validation.tests.versions.v108_7.mouse').run(self)
    require('validation.tests.versions.v108_7.windows').run(self)
    require('validation.tests.versions.v108_7.windowsLab').run(self)
    require('validation.tests.versions.v108_7.windowScene').run(self)
    require('validation.tests.versions.v108_7.actor').run(self)
    require('validation.tests.versions.v108_7.voiceWarmUp').run(self)
    require('validation.tests.versions.v108_7.botRoutes').run(self)
    require('validation.tests.versions.v108_7.closedWindowEvents').run(self)
    require('validation.tests.versions.v108_7.moveWindows').run(self)
    require('validation.tests.versions.v108_7.profileWindowScene').run(self)
    require('validation.tests.versions.v108_7.orbitGlide').run(self)
    require('validation.tests.versions.v108_7.dentShading').run(self)
    require('validation.tests.versions.v108_7.wheelRoll').run(self)
    require('validation.tests.versions.v108_7.sceneTags').run(self)
    require('validation.tests.versions.v108_7.botWorkers').run(self)
    require('validation.tests.versions.v108_7.nativePaths').run(self)
    require('validation.tests.versions.v108_7.collisionLevels').run(self)
    require('validation.tests.versions.v108_7.engineSound').run(self)
    require('validation.tests.versions.v108_7.labScenes').run(self)
    require('validation.tests.versions.v108_7.gamepad').run(self)
    require('validation.tests.versions.v108_7.postProcessing').run(self)
    require('validation.tests.versions.v108_7.animationTree').run(self)
    require('validation.tests.versions.v108_7.navMesh').run(self)
    require('validation.tests.versions.v108_7.navNodes').run(self)
    require('validation.tests.versions.v108_7.navLinks').run(self)
    require('validation.tests.versions.v108_7.tileMap').run(self)
    require('validation.tests.versions.v108_7.localization').run(self)
    require('validation.tests.versions.v108_7.hotReload').run(self)
    require('validation.tests.versions.v108_7.audioFormats').run(self)
    require('validation.tests.versions.v108_7.netConditions').run(self)
    require('validation.tests.versions.v108_7.dedicatedServer').run(self)
    require('validation.tests.versions.v108_7.serverBoundary').run(self)
    require('validation.tests.versions.v108_7.serverProcess').run(self)
    print('PASSED ' .. self.count .. ' v108.7 focused checks')
    katsa.event.quit()
end

return Tests
