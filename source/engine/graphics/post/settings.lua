-- Post-processing settings, shaped like Godot's Environment: every effect is its own section
-- (Glow, SSAO, DepthOfField, Adjustments) with an `enabled` switch, plus a small Vignette and
-- the screen-space anti-aliasing mode kept beside MSAA in Rendering. Defaults leave every
-- effect off, so a scene looks unchanged until it opts in.
--
-- Each section also describes its inspector rows (`keys`, `descriptors`) so the schema layer
-- needs no per-effect knowledge.
local Settings = {}

local BLEND_MODES = { 'Additive', 'Screen', 'Softlight', 'Replace', 'Mix' }
local QUALITIES = { 'Low', 'Medium', 'High' }

local function when(key)
    return { key = key, equals = true }
end

-- Environment field -> section definition. `order` fixes the Workspace row order.
Settings.sections = {
    {
        field = 'glow',
        title = 'Glow',
        defaults = {
            enabled = false,
            intensity = 0.8,
            strength = 1.0,
            mix = 0.05,
            bloom = 0.0,
            blendMode = 'Softlight',
            hdrThreshold = 0.8,
            hdrScale = 2.0,
            levels = 5,
        },
        keys = {
            'enabled',
            'intensity',
            'strength',
            'mix',
            'bloom',
            'blendMode',
            'hdrThreshold',
            'hdrScale',
            'levels',
        },
        descriptors = {
            intensity = { min = 0, max = 8, hint = 'Glow amount added to the image.' },
            strength = { min = 0, max = 2, hint = 'Blur spread: larger values widen the glow.' },
            mix = {
                min = 0,
                max = 1,
                hint = 'Replacement amount of the Mix blend mode.',
                visibleWhen = { key = 'blendMode', equals = 'Mix' },
            },
            bloom = {
                min = 0,
                max = 1,
                hint = 'Glow added from every pixel, not only the bright ones.',
            },
            blendMode = { options = BLEND_MODES, hint = 'How the glow combines with the image.' },
            hdrThreshold = {
                min = 0,
                max = 4,
                hint = 'Luminance above which pixels glow. Measured after tone mapping, 0..1.',
            },
            hdrScale = {
                min = 0,
                max = 8,
                hint = 'Glow multiplier applied to the part above the threshold.',
            },
            levels = { min = 1, max = 7, integer = true, hint = 'Blur levels: more is wider.' },
        },
    },
    {
        field = 'ssao',
        title = 'SSAO',
        defaults = {
            enabled = false,
            quality = 'Medium',
            radius = 1.0,
            intensity = 2.0,
            power = 1.5,
        },
        keys = { 'enabled', 'quality', 'radius', 'intensity', 'power' },
        descriptors = {
            quality = { options = QUALITIES, hint = 'Samples per pixel: 8, 12 or 20.' },
            radius = { min = 0.01, max = 50, hint = 'Occlusion search radius in world units.' },
            intensity = { min = 0, max = 16, hint = 'Darkening strength.' },
            power = { min = 0.1, max = 8, hint = 'Contrast of the darkening falloff.' },
        },
    },
    {
        field = 'volumetricFog',
        title = 'VolumetricFog',
        defaults = {
            enabled = false,
            density = 0.02,
            heightFalloff = 0.0,
            baseHeight = 0.0,
            color = { 200, 214, 235 },
            anisotropy = 0.6,
            lightEnergy = 1.0,
            ambient = 0.3,
            maxDistance = 120,
            shadows = true,
            skyAffect = 0.0,
            quality = 'Medium',
        },
        keys = {
            'enabled',
            'density',
            'heightFalloff',
            'baseHeight',
            'color',
            'anisotropy',
            'lightEnergy',
            'ambient',
            'maxDistance',
            'shadows',
            'skyAffect',
            'quality',
        },
        descriptors = {
            density = { min = 0, max = 2, hint = 'Fog thickness per world unit. 0.02 is light haze, 0.2 is thick.' },
            heightFalloff = {
                min = 0,
                max = 4,
                hint = 'How fast the fog thins above baseHeight. 0 = the same density at every height.',
            },
            baseHeight = { hint = 'World height where the fog has full density.' },
            color = { hint = 'Colour of the fog itself (0-255).' },
            anisotropy = {
                min = -0.95,
                max = 0.95,
                hint = 'Light scattering direction: positive brightens fog toward the sun (shafts), 0 is even.',
            },
            lightEnergy = { min = 0, max = 16, hint = 'Brightness of the sunlight scattered in the fog.' },
            ambient = { min = 0, max = 4, hint = 'Fog light that does not depend on the sun.' },
            maxDistance = { min = 1, hint = 'Fog is computed up to this distance from the camera.' },
            shadows = { hint = 'Sunlight in the fog respects the shadow map (light shafts).' },
            skyAffect = { min = 0, max = 1, hint = 'How much of the fog is also drawn over the sky.' },
            quality = {
                options = QUALITIES,
                hint = 'Low: half resolution, 16 steps. Medium: half resolution, 32 steps. High: full resolution, 48 steps.',
            },
        },
    },
    {
        field = 'depthOfField',
        title = 'DepthOfField',
        defaults = {
            enabled = false,
            farEnabled = true,
            farDistance = 10,
            farTransition = 5,
            nearEnabled = false,
            nearDistance = 2,
            nearTransition = 1,
            amount = 0.1,
            quality = 'Medium',
        },
        keys = {
            'enabled',
            'farEnabled',
            'farDistance',
            'farTransition',
            'nearEnabled',
            'nearDistance',
            'nearTransition',
            'amount',
            'quality',
        },
        descriptors = {
            farEnabled = { hint = 'Blur everything farther than farDistance.' },
            farDistance = {
                min = 0,
                hint = 'Distance in world units where far blur starts.',
                visibleWhen = when('farEnabled'),
            },
            farTransition = {
                min = 0.001,
                hint = 'Distance over which far blur grows to its maximum.',
                visibleWhen = when('farEnabled'),
            },
            nearEnabled = { hint = 'Blur everything closer than nearDistance.' },
            nearDistance = {
                min = 0,
                hint = 'Distance in world units where near blur starts.',
                visibleWhen = when('nearEnabled'),
            },
            nearTransition = {
                min = 0.001,
                hint = 'Distance over which near blur grows to its maximum.',
                visibleWhen = when('nearEnabled'),
            },
            amount = { min = 0, max = 1, hint = 'Largest blur radius, as a share of the view height.' },
            quality = { options = QUALITIES, hint = 'Samples per pixel: 8, 16 or 32.' },
        },
    },
    {
        field = 'adjustments',
        title = 'Adjustments',
        defaults = {
            enabled = false,
            brightness = 1.0,
            contrast = 1.0,
            saturation = 1.0,
            colorCorrection = '',
            colorCorrectionStrength = 1.0,
        },
        keys = {
            'enabled',
            'brightness',
            'contrast',
            'saturation',
            'colorCorrection',
            'colorCorrectionStrength',
        },
        descriptors = {
            brightness = { min = 0, max = 8, hint = 'Multiplies the image.' },
            contrast = { min = 0, max = 8, hint = 'Spreads values around middle grey.' },
            saturation = { min = 0, max = 8, hint = '0 is greyscale, 1 unchanged.' },
            colorCorrection = {
                hint = 'Lookup-table image: a strip of N slices, N*N wide and N tall '
                    .. '(for example 256x16). Empty disables it.',
            },
            colorCorrectionStrength = {
                min = 0,
                max = 1,
                hint = 'Mix between the original and the corrected colors.',
                visibleWhen = { key = 'colorCorrection', present = true },
            },
        },
    },
    {
        field = 'vignette',
        title = 'Vignette',
        defaults = {
            enabled = false,
            intensity = 0.4,
            radius = 0.8,
            softness = 0.5,
        },
        keys = { 'enabled', 'intensity', 'radius', 'softness' },
        descriptors = {
            intensity = { min = 0, max = 1, hint = 'How dark the corners get.' },
            radius = { min = 0, max = 2, hint = 'Distance from the centre where darkening starts.' },
            softness = { min = 0.01, max = 2, hint = 'Width of the fade.' },
        },
    },
}

Settings.antialiasing = { 'Disabled', 'FXAA' }

local byKind = {}
for _, section in ipairs(Settings.sections) do
    section.kind = section.title
    byKind[section.kind] = section
end

function Settings.definition(kind)
    return byKind[kind]
end

-- Adds every missing section (and missing key of a section) to an Environment.
function Settings.install(environment)
    for _, section in ipairs(Settings.sections) do
        local values = environment[section.field] or {}
        environment[section.field] = values
        values._settingsKind = section.kind
        for key, default in pairs(section.defaults) do
            if values[key] == nil then
                -- Colours are tables: each Environment gets its own copy.
                values[key] = type(default) == 'table' and { unpack(default) } or default
            end
        end
    end
    if environment.render.screenSpaceAA == nil then
        environment.render.screenSpaceAA = 'Disabled'
    end
end

-- True when at least one effect would change the image.
function Settings.active(environment)
    for _, section in ipairs(Settings.sections) do
        local values = environment[section.field]
        if values and values.enabled == true then
            return true
        end
    end
    return environment.render.screenSpaceAA == 'FXAA'
end

return Settings
