-- stareShooter starts with the camera behind the character, not in first person.
local Application = require('source.game.runtime.application')

local Module = {}

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    self:check(scene.demo.orbit.distance > 0.5, 'stareShooter starts in third person')
    scene:release()
end

return Module
