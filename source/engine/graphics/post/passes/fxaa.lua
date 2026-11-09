-- Screen-space anti-aliasing (Godot's `screen_space_aa = FXAA`).
local Fullscreen = require('../fullscreen')

local FXAA = {}

function FXAA.run(ctx, input, destination)
    local shader = Fullscreen.shader(ctx.post, ctx.renderer, 'fxaa')
    local width, height = input:getPixelDimensions()
    Fullscreen.send(shader, 'texel', { 1 / width, 1 / height })
    Fullscreen.draw(input, shader, destination)
end

return FXAA
