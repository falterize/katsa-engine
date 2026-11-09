-- SSAO: occlusion from the scene depth at half resolution, blurred with depth awareness, then
-- multiplied into the image.
local Targets = require('../targets')
local Fullscreen = require('../fullscreen')

local SSAO = {}

local SAMPLES = { Low = 8, Medium = 12, High = 20 }
local BIAS = 0.03

function SSAO.run(ctx, input, destination)
    local post, renderer, settings = ctx.post, ctx.renderer, ctx.environment.ssao
    local depth = ctx:depth()
    local occlusion = Targets.get(post.targets, renderer, 'occlusion', 2)
    local scratch = Targets.get(post.targets, renderer, 'occlusionBlur', 2)
    local width, height = occlusion:getPixelDimensions()

    local trace = Fullscreen.shader(post, renderer, 'ssao')
    ctx:sendCamera(trace)
    Fullscreen.send(trace, 'depthTexture', depth)
    Fullscreen.send(trace, 'depthSize', { depth:getPixelWidth(), depth:getPixelHeight() })
    Fullscreen.send(trace, 'radius', settings.radius)
    Fullscreen.send(trace, 'bias', BIAS * math.max(1, settings.radius))
    Fullscreen.send(trace, 'sampleCount', SAMPLES[settings.quality] or SAMPLES.Medium)
    Fullscreen.draw(input, trace, occlusion)

    local blur = Fullscreen.shader(post, renderer, 'ssaoBlur')
    ctx:sendCamera(blur)
    Fullscreen.send(blur, 'depthTexture', depth)
    Fullscreen.send(blur, 'direction', { 1 / width, 0 })
    Fullscreen.draw(occlusion, blur, scratch)
    Fullscreen.send(blur, 'direction', { 0, 1 / height })
    Fullscreen.draw(scratch, blur, occlusion)

    local apply = Fullscreen.shader(post, renderer, 'ssaoApply')
    Fullscreen.send(apply, 'occlusionTexture', occlusion)
    Fullscreen.send(apply, 'intensity', settings.intensity)
    Fullscreen.send(apply, 'power', settings.power)
    Fullscreen.draw(input, apply, destination)
end

return SSAO
