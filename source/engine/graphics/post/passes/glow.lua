-- Glow: a bright pass, a chain of halving blurs and a tent upsample that accumulates every level
-- into the first. Returns the half-resolution glow texture for the finish pass.
local Targets = require('../targets')
local Fullscreen = require('../fullscreen')

local Glow = {}

function Glow.build(ctx, input)
    local post, renderer, settings = ctx.post, ctx.renderer, ctx.environment.glow
    local levels = math.max(1, math.min(7, math.floor(settings.levels)))
    local down = Fullscreen.shader(post, renderer, 'glowDown')
    local up = Fullscreen.shader(post, renderer, 'glowUp')
    local chain = {}
    local source = input
    for level = 1, levels do
        local target = Targets.get(post.targets, renderer, 'glow' .. level, 2 ^ level)
        local sourceWidth, sourceHeight = source:getPixelDimensions()
        Fullscreen.send(down, 'texel', { 0.5 / sourceWidth, 0.5 / sourceHeight })
        Fullscreen.send(down, 'firstLevel', level == 1)
        Fullscreen.send(down, 'threshold', settings.hdrThreshold)
        Fullscreen.send(down, 'scale', settings.hdrScale)
        Fullscreen.send(down, 'bloom', settings.bloom)
        Fullscreen.draw(source, down, target)
        chain[level] = target
        source = target
    end
    for level = levels - 1, 1, -1 do
        local low = chain[level + 1]
        local width, height = low:getPixelDimensions()
        Fullscreen.send(up, 'texel', { 1 / width, 1 / height })
        Fullscreen.send(up, 'spread', 0.5 + settings.strength)
        Fullscreen.draw(low, up, chain[level], 'add')
    end
    return chain[1]
end

return Glow
