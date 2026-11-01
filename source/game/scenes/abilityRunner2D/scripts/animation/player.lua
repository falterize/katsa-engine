local FlipbookXml = require('source.engine.animation.formats.flipbookXml')
local Animation = {}

function Animation.create(state)
    return FlipbookXml.playback(state.scene.resources, state.sprite)
end

return Animation
