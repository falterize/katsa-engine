-- Multiplayer cars: LAN server list, authoritative server, bot and nitro refill by rewarded ad.
-- This file only wires the lifecycle; the pieces live in nodes/, scripts/ and systems/.
local Scene = {}

function Scene.create(scene, context)
    context.instance = { scene = scene }
end

function Scene.update() end
function Scene.update3D() end
function Scene.update2D() end
function Scene.destroy() end

return Scene
