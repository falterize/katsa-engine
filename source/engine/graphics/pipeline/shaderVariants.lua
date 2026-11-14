local Lighting = require('../../components.illumination.lighting')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Constant-disabled paths remove unused uniforms and branches from the GPU program.
-- Enabled features always retain the complete shader and its original calculations.
local Variants = {}
local Opaque = require('../materials.opaqueMesh')
local surfaceMaps = { 'normalMap', 'roughnessMap', 'metalnessMap', 'occlusionMap', 'emissionMap' }

function Variants.get(renderer, object)
    local solid = Opaque.eligible(object, renderer)
    local earlyDepth = renderer.depthPrepassActive == true
    local noDirections = true
    for _, light in ipairs(renderer.lights.selected) do
        if light.type == 'DirectionalLight3D' and light.enabled and not light.destroyed then
            noDirections = false
            break
        end
    end
    local noLights = renderer.lights.count == 0
    local lightCount = renderer.lights.count
    local unlit = object and Lighting.unlit(object) or false
    local noSkin = not (object and object.skin)
    local extendedSkin = not noSkin and object.geometry.eightWeights == true
    local direct = renderer.lightLoop ~= 'Masked'
    local noShadows = not renderer.world.environment.shadows.enabled
        or object and object.receiveShadow == false
    local shadows = renderer.world.environment.shadows
    local standardShadows = shadows.mode == nil or shadows.mode == 'Standard'
    local filterSamples = shadows.filterSamples
    local surface = object and object._surfaceAppearance
    local noMaps = surface ~= nil
    for _, name in ipairs(surfaceMaps) do
        if surface and surface[name] and surface[name] ~= '' then
            noMaps = false
            break
        end
    end
    if
        renderer.forceGeneralShader
        or not noSkin and not noShadows and not noMaps and not direct
    then
        return renderer.shader
    end
    local key = (noSkin and 'rigid' or 'skin')
        .. (extendedSkin and ':eight' or ':four')
        .. (noShadows and ':clear' or ':shadow')
        .. (noMaps and ':plain' or ':mapped')
        .. (direct and ':direct' or ':masked')
        .. (
            noShadows and ''
            or ':sources' .. (standardShadows and ':pcf' .. tostring(filterSamples) or ':soft')
        )
    key = key
        .. (solid and ':solid' or ':alpha')
        .. (earlyDepth and ':depth' or ':noDepth')
        .. (noDirections and ':local' or ':directional')
        .. (noLights and ':zero' or ':lit')
        .. ':lights'
        .. lightCount
        .. (unlit and ':unlit' or ':shaded')
    renderer.shaderVariants = renderer.shaderVariants or {}
    local uses = renderer.shaderVariantUses or {}
    renderer.shaderVariantUses = uses
    uses[key] = renderer.frame
    local shader = renderer.shaderVariants[key]
    if not shader then
        local defines = {
            KATSA_EARLY_DEPTH = earlyDepth,
            KATSA_SOLID = solid,
            KATSA_NO_DIRECTIONAL = noDirections,
            -- Without the per-object light mask the whole interface is excluded, not just the
            -- arithmetic, so GLES drivers never see the unused varying and attribute.
            KATSA_LIGHT_MASK = not direct,
            KATSA_SHADOW_STANDARD = not noShadows and standardShadows,
            KATSA_SHADOW_SAMPLES = not noShadows and standardShadows and filterSamples or false,
        }
        local constants = {
            -- The selected light count is fixed for this draw: the GPU compiler sees the real
            -- loop bound while the slots and equations stay those of the general program.
            lightCount = lightCount,
            unlit = unlit,
            skinExtended = extendedSkin,
        }
        if noSkin then
            constants.skinEnabled = false
        end
        if noShadows then
            constants.receiveShadow = false
        end
        if solid then
            constants.decalTexture = false
            constants.canvasTexture = false
        end
        if noMaps then
            constants.surfaceEnabled = true
            for _, name in ipairs({
                'hasNormalMap',
                'hasRoughnessMap',
                'hasMetalnessMap',
                'hasOcclusionMap',
                'hasEmissionMap',
            }) do
                constants[name] = false
            end
        end
        shader = renderer.resources:own(
            (require('source.engine.graphics.shaders.programs').compile(
                'assets/shaders/engine/world.glsl',
                { defines = defines, constants = constants }
            ))
        )
        renderer.shaderVariants[key] = shader
        renderer.shaderVariantCount = (renderer.shaderVariantCount or 0) + 1
        if renderer.shaderVariantCount > 64 then
            local oldest, oldFrame
            for candidate, frame in pairs(uses) do
                if
                    candidate ~= key
                    and frame < renderer.frame
                    and (not oldFrame or frame < oldFrame)
                then
                    oldest, oldFrame = candidate, frame
                end
            end
            if oldest then
                local retired = renderer.shaderVariants[oldest]
                renderer.shaderFrames[retired] = nil
                renderer.resources:releaseOwned(retired)
                renderer.shaderVariants[oldest], uses[oldest] = nil, nil
                renderer.shaderVariantCount = renderer.shaderVariantCount - 1
            end
        end
    end
    return shader
end

return Variants
