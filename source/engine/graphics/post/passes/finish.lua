-- Glow blend, Adjustments (brightness, contrast, saturation, colour-correction lookup table)
-- and Vignette in one pass over the image.
local Fullscreen = require('../fullscreen')
local Glow = require('./glow')

local Finish = {}

local MODES = { Additive = 0, Screen = 1, Softlight = 2, Replace = 3, Mix = 4 }

-- The lookup table image (a strip of N slices, N*N wide and N tall), cached per path.
local function lookupTable(ctx, path)
    local post = ctx.post
    if post.lutPath ~= path then
        post.lutPath, post.lut = path, nil
        if path ~= '' then
            local image = ctx.renderer.world.resources:image(path)
            image:setFilter('linear', 'linear')
            pcall(image.setMipmapFilter, image, nil)
            post.lut = image
        end
    end
    return post.lut
end

function Finish.needed(environment)
    return environment.glow.enabled
        or environment.adjustments.enabled
        or environment.vignette.enabled
end

function Finish.run(ctx, input, destination)
    local post, renderer, environment = ctx.post, ctx.renderer, ctx.environment
    local shader = Fullscreen.shader(post, renderer, 'finish')
    local glow, adjust, vignette = environment.glow, environment.adjustments, environment.vignette

    Fullscreen.send(shader, 'glowEnabled', glow.enabled == true)
    if glow.enabled then
        Fullscreen.send(shader, 'glowTexture', Glow.build(ctx, input))
        Fullscreen.send(shader, 'glowIntensity', glow.intensity)
        Fullscreen.send(shader, 'glowMix', glow.mix)
        Fullscreen.send(shader, 'glowMode', MODES[glow.blendMode] or MODES.Softlight)
    end
    Fullscreen.send(shader, 'adjustEnabled', adjust.enabled == true)
    Fullscreen.send(shader, 'adjust', { adjust.brightness, adjust.contrast, adjust.saturation })
    local lut = adjust.enabled and lookupTable(ctx, adjust.colorCorrection or '') or nil
    Fullscreen.send(shader, 'lutEnabled', lut ~= nil)
    if lut then
        Fullscreen.send(shader, 'lutTexture', lut)
        Fullscreen.send(shader, 'lutSize', lut:getHeight())
        Fullscreen.send(shader, 'lutStrength', adjust.colorCorrectionStrength)
    end
    Fullscreen.send(shader, 'vignetteEnabled', vignette.enabled == true)
    Fullscreen.send(shader, 'vignette', { vignette.intensity, vignette.radius, vignette.softness })
    Fullscreen.send(shader, 'aspect', renderer.width / math.max(1, renderer.height))
    Fullscreen.draw(input, shader, destination)
end

return Finish
