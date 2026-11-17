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
    require('validation.tests.versions.v108_8.animationNodes').run(self)
    require('validation.tests.versions.v108_8.additivePose').run(self)
    require('validation.tests.versions.v108_8.clipPlayback').run(self)
    require('validation.tests.versions.v108_8.graphNodes').run(self)
    require('validation.tests.versions.v108_8.realClips').run(self)
    require('validation.tests.versions.v108_8.physicsAccess').run(self)
    require('validation.tests.versions.v108_8.shaderComposer').run(self)
    require('validation.tests.versions.v108_8.shaderPrograms').run(self)
    require('validation.tests.versions.v108_8.environmentShaders').run(self)
    require('validation.tests.versions.v108_8.uniformEditor').run(self)
    require('validation.tests.versions.v108_8.shaderFollowups').run(self)
    require('validation.tests.versions.v108_8.replication').run(self)
    require('validation.tests.versions.v108_8.replicationLab').run(self)
    require('validation.tests.versions.v108_8.imgui').run(self)
    require('validation.tests.versions.v108_8.uiMeasure').run(self)
    require('validation.tests.versions.v108_8.sceneRoot').run(self)
    require('validation.tests.versions.v108_8.nodePaths').run(self)
    require('validation.tests.versions.v108_8.shaderTags').run(self)
    require('validation.tests.versions.v108_8.noOpProperties').run(self)
    require('validation.tests.versions.v108_8.stareCamera').run(self)
    require('validation.tests.versions.v108_8.shaderTagDepth').run(self)
    require('validation.tests.versions.v108_8.ssaoDepth').run(self)
    require('validation.tests.versions.v108_8.ssaoQuality').run(self)
    require('validation.tests.versions.v108_8.ragdoll').run(self)
    require('validation.tests.versions.v108_8.packedScene').run(self)
    require('validation.tests.versions.v108_8.packedViewport').run(self)
    require('validation.tests.versions.v108_8.uiFrames').run(self)
    require('validation.tests.versions.v108_8.lod').run(self)
    require('validation.tests.versions.v108_8.lodImport').run(self)
    require('validation.tests.versions.v108_8.lodEffects').run(self)
    require('validation.tests.versions.v108_8.stareLod').run(self)
    require('validation.tests.versions.v108_8.engineVersion').run(self)
    print('PASSED ' .. self.count .. ' v108.8 focused checks')
    katsa.event.quit()
end

return Tests
