-- Multiplayer cars client: LAN server list, driving, chat, voice and nitro refill by rewarded ad.
-- This file only wires the lifecycle; the game lives in scripts/ and the car in nodes/vehicle/.
-- The authoritative server is server/ (settings.server): `--server` runs it instead of this file.
local Scene = {}

function Scene.create(scene, context)
    local Session = context:require('scripts.content')
    -- Esc opens the pause menu without stopping time: the host's server must keep simulating.
    require('source.game.runtime.pauseMenu').attach(scene, true)
    scene:preparePresentation()
    local state = Session.new(scene)
    context.instance = state
    return state
end

function Scene.update(state, dt)
    state:update(dt)
end

-- Advances the world's nodes: the character animators and everything else that animates.
function Scene.update3D(state, dt)
    state.scene.world:updateNodes(dt)
end

function Scene.update2D(state, dt, realDt)
    local scene = state.scene
    scene.ui:update(realDt or dt, dt)
end

function Scene.destroy(state)
    state:release()
end

return Scene
