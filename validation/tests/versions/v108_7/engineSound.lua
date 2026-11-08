-- Engine note: revs climb in a gear and drop at the shift; the asset stays small.
local Tests = {}

function Tests.run(tester)
    local package = tester.manager.resources
    local EngineSound = dofile('source/game/scenes/multiplayerCars/scripts/view/engineSound.lua')
    tester:check(EngineSound.revs(0) < EngineSound.revs(13), 'revs climb inside the first gear')
    tester:check(EngineSound.revs(15) < EngineSound.revs(13), 'revs drop after a gear shift')
    tester:check(EngineSound.revs(-20) == EngineSound.revs(20), 'reverse sounds like forward')
    local idlePitch, idleVolume = EngineSound.tone(0, 0)
    local topPitch, topVolume = EngineSound.tone(1, 1)
    tester:check(topPitch > idlePitch and topVolume > idleVolume, 'higher revs are faster and louder')
    local info = katsa.filesystem.getInfo('source/game/scenes/multiplayerCars/assets/audio/engineLoop.ogg')
    tester:check(info and info.size < 1024 * 1024, 'the engine loop is under one megabyte')
    tester:check(package ~= nil, 'resources available')
end

return Tests
