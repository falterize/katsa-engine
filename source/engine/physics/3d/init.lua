-- Public facade: assemble physics responsibilities once at module load.
local O = require('./valueTypes')

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
Physics.backends = require('./backends.registry')
Physics.setDefaultBackend = Physics.backends.setDefault

local Body3D = {}
Body3D.__index = Body3D

require('./internal.creation').install(Physics, Body3D)
require('./internal.gravity').install(Physics)
require('./internal.colliders').install(Physics, Body3D)
require('./internal.bodyProperties').install(Physics, Body3D)
require('./internal.bodyMotion').install(Physics, Body3D)
require('./internal.lifecycle').install(Physics, Body3D)
require('./internal.simulation').install(Physics, Body3D)
require('./internal.queries').install(Physics, Body3D)
require('./internal.joints').install(Physics, Body3D)
require('./internal.debugDrawing').install(Physics, Body3D)
require('./internal.modelCollider').install(Physics, Body3D)
require('./bodyExtensions').install(Body3D, Physics, O)
require('./interpolation').install(Body3D, O, Physics)

function Physics.extractMeshPoints(source, body, options)
    return require('./pointCollider').extract(source, body, options)
end

return Physics
