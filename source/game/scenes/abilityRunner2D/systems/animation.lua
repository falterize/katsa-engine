local Clock = require('source.engine.world.clock')
local Animation = {}
Animation.__index = Animation

function Animation.create(state)
    local flipbook = state.scene.package:require('scripts.animation.player').create(state)
    return setmetatable({ state = state, flipbook = flipbook, elapsed = 0 }, Animation)
end

function Animation:update2D(dt)
    local state = self.state
    dt = Clock.delta(state.scene.ui, dt)
    if dt <= 0 then
        return
    end
    self.flipbook:play(state.controller.motion)
    self.flipbook:update(dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed >= 0.1 then
        self.elapsed = self.elapsed % 0.1
        if state.status then
            state.status.text = string.format(
                '%s | Checkpoint %d/%d | Respawns %d | %s',
                state.completed and 'Finished!' or 'Ability Runner 2D',
                state.checkpoint,
                #state.checkpoints,
                state.deaths,
                state.controller.motion
            )
        end
    end
end

return Animation
