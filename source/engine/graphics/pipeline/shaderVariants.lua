local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Constant-disabled paths remove unused uniforms and branches from the GPU program.
-- Enabled features always retain the complete shader and its original calculations.
local Variants = {}
local Opaque = require('../../materials.opaqueMesh')
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
    local unlit = object
            and (object.canvas ~= nil or object.unlit or object._systemEffects and not object._systemEffects.lighting)
        or false
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
        local source =
            require('source.engine.graphics.shaderSource').read('assets/shaders/engine/world.glsl')
        if not earlyDepth then
            source = source:gsub('// EARLY_DEPTH_BEGIN.-// EARLY_DEPTH_END', '')
        end
        if solid then
            source = source:gsub('if %(texel.a<=alphaCutoff%) discard;', '')
            source = source:gsub('uniform bool decalTexture;', 'const bool decalTexture=false;')
            source = source:gsub('uniform bool canvasTexture;', 'const bool canvasTexture=false;')
        end
        if noDirections then
            source = source:gsub('if%(lightExtra%[i%].y>1.5%)', 'if(false)')
        end
        -- The selected light count is fixed for this draw. Keep the same light
        -- slots/equations while exposing the real loop bound to the GPU compiler.
        source =
            source:gsub('uniform int lightCount;', 'const int lightCount=' .. lightCount .. ';')
        source = source:gsub('i<32;', 'i<' .. lightCount .. ';')
        source = source:gsub('uniform bool unlit;', 'const bool unlit=' .. tostring(unlit) .. ';')
        if direct then
            source = source:gsub(
                'uniform bool objectLightMaskEnabled;',
                'const bool objectLightMaskEnabled=false;'
            )
            -- Exclude the interface and arithmetic without relying on GLES dead-code removal.
            source = source
                :gsub('flat varying highp vec2 relevantLights;', '')
                :gsub('uniform highp vec2 objectLights1;', '')
                :gsub('attribute highp vec2 instanceLights1;', '')
                :gsub('relevantLights=[^\n]*', '')
                :gsub('uint lightMask=[^\n]*', '')
                :gsub('if%(objectLightMaskEnabled[^\n]*', '')
        end
        if noSkin then
            source = source:gsub('uniform bool skinEnabled;', 'const bool skinEnabled=false;')
        end
        source = source:gsub(
            'uniform bool skinExtended;',
            'const bool skinExtended=' .. tostring(extendedSkin) .. ';'
        )
        if noShadows then
            source = source:gsub('uniform bool receiveShadow;', 'const bool receiveShadow=false;')
        end
        if not noShadows then
            -- Specialize only built-in programs. Quality settings select equivalent
            -- calculations; custom materials retain their authored uniform interface.
            if standardShadows then
                source = source:gsub('if%(shadowSoftness.x>0.5%)', 'if(false)')
                source = source:gsub(
                    'int samples = int%(shadowParameters.w%);',
                    'int samples = ' .. tostring(filterSamples) .. ';'
                )
            end
        end
        if noMaps then
            source = source:gsub('uniform bool surfaceEnabled;', 'const bool surfaceEnabled=true;')
            for _, name in ipairs({
                'NormalMap',
                'RoughnessMap',
                'MetalnessMap',
                'OcclusionMap',
                'EmissionMap',
            }) do
                source = source:gsub(
                    'uniform bool has' .. name .. ';',
                    'const bool has' .. name .. '=false;'
                )
            end
        end
        shader = renderer.resources:own(katsa.graphics.newShader(source))
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
