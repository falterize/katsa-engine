-- Volumetric fog: a ray march through the fog between the camera and the scene depth, lit by
-- the sun (with its cascaded shadows, so trees and walls cast light shafts) and an ambient term,
-- composited over the image. The march runs at half resolution on Low and Medium.
local Targets = require('../targets')
local Fullscreen = require('../fullscreen')

local VolumetricFog = {}

local QUALITY = {
    Low = { steps = 16, divisor = 2 },
    Medium = { steps = 32, divisor = 2 },
    High = { steps = 48, divisor = 1 },
}

-- The brightest directional light among the lights the renderer uploaded, with its slot.
local function sun(renderer)
    local lights, best, bestEnergy = renderer.lights, nil, -1
    for i = 1, lights.count or 0 do
        if lights.extra[i][2] > 1.5 then
            local energy = lights.color[i][4]
            if energy > bestEnergy then
                best, bestEnergy = i, energy
            end
        end
    end
    return best
end

function VolumetricFog.run(ctx, input, destination)
    local post, renderer, settings = ctx.post, ctx.renderer, ctx.environment.volumetricFog
    local quality = QUALITY[settings.quality] or QUALITY.Medium
    local target = Targets.get(post.targets, renderer, 'volumetricFog', quality.divisor)
    local shader = Fullscreen.shader(post, renderer, 'volumetricFog')
    local camera = ctx.camera
    ctx:sendCamera(shader)
    local depth = ctx:depth()
    Fullscreen.send(shader, 'depthTexture', depth)
    Fullscreen.send(shader, 'cameraPosition', camera.worldPosition or camera.position)
    Fullscreen.send(shader, 'cameraRight', camera.right)
    Fullscreen.send(shader, 'cameraUp', camera.up)
    Fullscreen.send(shader, 'cameraForward', camera.forward)
    Fullscreen.send(shader, 'density', settings.density)
    Fullscreen.send(shader, 'heightFalloff', settings.heightFalloff)
    Fullscreen.send(shader, 'baseHeight', settings.baseHeight)
    local c = settings.color
    Fullscreen.send(shader, 'fogColor', { c[1] / 255, c[2] / 255, c[3] / 255 })
    Fullscreen.send(shader, 'anisotropy', settings.anisotropy)
    Fullscreen.send(shader, 'ambientEnergy', settings.ambient)
    Fullscreen.send(shader, 'maxDistance', settings.maxDistance)
    Fullscreen.send(shader, 'skyAffect', settings.skyAffect)
    Fullscreen.send(shader, 'stepCount', quality.steps)
    local slot = sun(renderer)
    Fullscreen.send(shader, 'sunEnabled', slot ~= nil)
    if slot then
        local lights = renderer.lights
        local direction, color = lights.direction[slot], lights.color[slot]
        Fullscreen.send(shader, 'sunToward', { -direction[1], -direction[2], -direction[3] })
        local energy = color[4] * settings.lightEnergy
        Fullscreen.send(shader, 'sunRadiance', { color[1] * energy, color[2] * energy, color[3] * energy })
        local shadowed = settings.shadows and renderer.shadows.enabled
        Fullscreen.send(shader, 'sunIndex', shadowed and slot - 1 or -1)
        if shadowed then
            renderer.shadows:send(shader, renderer.world.lighting)
        end
    end
    Fullscreen.draw(input, shader, target)

    local apply = Fullscreen.shader(post, renderer, 'volumetricFogApply')
    Fullscreen.send(apply, 'fogTexture', target)
    Fullscreen.draw(input, apply, destination)
end

return VolumetricFog
