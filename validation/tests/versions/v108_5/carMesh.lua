-- Car bodies are lofted once and shared as a rest pose; each car keeps its own dentable vertices.
local Body = require('source.game.scenes.multiplayerCars.scripts.view.carMesh')

local Module = {}

function Module.run(self)
    local paintA, glassA = Body.create()
    local started = os.clock()
    local paintB = Body.create()
    local elapsed = os.clock() - started

    self:check(paintA.rest == paintB.rest, 'cars share one rest pose')
    self:check(
        paintA.geometry.vertices ~= paintB.geometry.vertices
            and paintA.geometry.vertices[1] ~= paintB.geometry.vertices[1],
        'each car owns its own vertices'
    )

    local before = paintB.geometry.vertices[1][1]
    local dents = { offsetAt = function() return 0.5, 0, 0 end }
    Body.deform(paintA.geometry, paintA.rest, dents)
    self:check(
        paintB.geometry.vertices[1][1] == before and paintA.rest[1][1] ~= paintA.geometry.vertices[1][1],
        'denting one car leaves the rest pose and other cars alone'
    )
    self:check(#glassA.rest > 0 and glassA.geometry.mesh ~= nil, 'glass part has a mesh')
    self:check(elapsed < 0.03, 'creating another car body takes under 30 ms (' .. math.floor(elapsed * 1000) .. ' ms)')
end

return Module
