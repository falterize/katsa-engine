-- Depth of field: far and near blur like Godot's camera attributes.
local Fullscreen = require('../fullscreen')

local DOF = {}

local SAMPLES = { Low = 8, Medium = 16, High = 32 }
local RADIUS_SHARE = 0.1 -- amount 1 blurs by 10% of the view height

function DOF.run(ctx, input, destination)
    local post, renderer, settings = ctx.post, ctx.renderer, ctx.environment.depthOfField
    local depth = ctx:depth()
    local shader = Fullscreen.shader(post, renderer, 'dof')
    ctx:sendCamera(shader)
    local pixelWidth, pixelHeight = input:getPixelDimensions()
    Fullscreen.send(shader, 'depthTexture', depth)
    Fullscreen.send(shader, 'texel', { 1 / pixelWidth, 1 / pixelHeight })
    Fullscreen.send(shader, 'maxRadius', settings.amount * RADIUS_SHARE * pixelHeight)
    Fullscreen.send(shader, 'farEnabled', settings.farEnabled == true)
    Fullscreen.send(shader, 'farRange', { settings.farDistance, settings.farTransition })
    Fullscreen.send(shader, 'nearEnabled', settings.nearEnabled == true)
    Fullscreen.send(shader, 'nearRange', { settings.nearDistance, settings.nearTransition })
    Fullscreen.send(shader, 'sampleCount', SAMPLES[settings.quality] or SAMPLES.Medium)
    Fullscreen.draw(input, shader, destination)
end

return DOF
