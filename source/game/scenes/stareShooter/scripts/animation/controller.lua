local Math = require('scene.scripts.controller.math')

local Animation = {}
Animation.__index = Animation

function Animation.new(player)
    local tracks = {}
    for _, name in ipairs({ 'Idle', 'Walk', 'Crouch', 'Fall', 'Jump' }) do
        local track = player.model.animator:load('Player_' .. name, { looped = name ~= 'Jump' })
        track:play(0, name == 'Jump' and 2 or 1, name == 'Idle' and 1 or 0)
        tracks[name] = track
    end
    return setmetatable(
        { player = player, tracks = tracks, airBlend = 0, jumpSequence = 0, jumpTime = 1 },
        Animation
    )
end

function Animation:update(dt)
    local player, tracks = self.player, self.tracks
    self.airBlend = Math.approach(self.airBlend, player.air and 1 or 0, dt / 0.25)
    if self.jumpSequence ~= player.jumpSequence then
        self.jumpSequence, self.jumpTime = player.jumpSequence, 0
        tracks.Jump:play(0, 2, 0)
    end
    self.jumpTime = self.jumpTime + dt
    local duration = tracks.Jump.clip.duration / 2
    local jumpWeight =
        math.min(1, math.max(0, self.jumpTime / 0.1), math.max(0, (duration - self.jumpTime) / 0.1))
    local ground = 1 - self.airBlend
    local physics, smooth = player.body.physics, player.smooth
    local walkBlend, crouchBlend = smooth.walk:sampleFor(physics), smooth.crouch:sampleFor(physics)
    tracks.Idle.weight = ground * (1 - crouchBlend) * (1 - walkBlend)
    tracks.Walk.weight = ground * (1 - crouchBlend) * walkBlend
    tracks.Crouch.weight = ground * crouchBlend
    tracks.Fall.weight = self.airBlend * (1 - jumpWeight)
    tracks.Jump.weight = self.airBlend * jumpWeight
    tracks.Walk.speed, tracks.Crouch.speed = player.walkScale, player.walkScale
    player.model.root.rotation[2] = math.deg(smooth.yaw:sampleFor(physics))
end

return Animation
