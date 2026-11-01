-- Public facade: assemble physics responsibilities once at module load.
local O = require('source.engine.physics.3d.valueTypes')

local Physics = {}
Physics.__index = function(self, key)
    if key == 'debugEnabled' then
        return self._debugSettings.enabled
    end
    return Physics[key]
end

Physics.__newindex = function(self, key, value)
    if key == 'debugEnabled' then
        self._debugSettings.enabled = value == true
    else
        rawset(self, key, value)
    end
end

function Physics:bindDebug(settings)
    if self._debugSettings.enabled then
        settings.enabled = true
    end
    self._debugSettings = settings
end

Physics.valueTypes = O
Physics.backend = O -- Historical public alias; this is a value API, not the solver.
Physics.backends = require('source.engine.physics.3d.backends.registry')
Physics.setDefaultBackend = Physics.backends.setDefault

local Body3D = {}
Body3D.__index = Body3D

require('source.engine.physics.3d.internal.creation').install(Physics, Body3D)
require('source.engine.physics.3d.internal.gravity').install(Physics)
require('source.engine.physics.3d.internal.colliders').install(Physics, Body3D)
require('source.engine.physics.3d.internal.bodyProperties').install(Physics, Body3D)
require('source.engine.physics.3d.internal.bodyMotion').install(Physics, Body3D)
require('source.engine.physics.3d.internal.lifecycle').install(Physics, Body3D)
require('source.engine.physics.3d.internal.simulation').install(Physics, Body3D)
require('source.engine.physics.3d.internal.queries').install(Physics, Body3D)
require('source.engine.physics.3d.internal.joints').install(Physics, Body3D)
require('source.engine.physics.3d.internal.debugDrawing').install(Physics, Body3D)
require('source.engine.physics.3d.internal.modelCollider').install(Physics, Body3D)
require('source.engine.physics.3d.bodyExtensions').install(Body3D, Physics, O)
require('source.engine.physics.3d.interpolation').install(Body3D, O, Physics)

function Physics.extractMeshPoints(source, body, options)
    return require('source.engine.physics.3d.pointCollider').extract(source, body, options)
end

return Physics
