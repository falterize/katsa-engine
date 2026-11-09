-- Post-processing settings, shaped like Godot's Environment: every effect is its own section
-- (Glow, SSAO, DepthOfField, Adjustments) with an `enabled` switch, the screen-space
-- anti-aliasing mode kept beside MSAA in Rendering, and the scene Fog with its volumetric mode.
-- Defaults leave every effect off, so a scene looks unchanged until it opts in.
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
        -- The scene's distance fog. `volumetric` switches it from a per-pixel blend to a ray
        -- march lit by the sun and every point/spot light; it is not a post effect by itself.
        field = 'fog',
        title = 'Fog',
        chain = false,
        defaults = {
            volumetric = false,
            heightFalloff = 0.0,
            baseHeight = 0.0,
            anisotropy = 0.6,
            lightEnergy = 1.0,
            lightClearing = 0.5,
            ambient = 0.3,
            volumetricDistance = 120,
            shadows = true,
            skyAffect = 0.0,
            quality = 'Medium',
        },
        keys = {
            'enabled',
            'color',
            'density',
            'mode',
            'offset',
            'endDistance',
            'maxOpacity',
            'volumetric',
            'quality',
            'volumetricDistance',
            'heightFalloff',
            'baseHeight',
            'anisotropy',
            'lightEnergy',
            'lightClearing',
            'ambient',
            'shadows',
            'skyAffect',
        },
        descriptors = {
            density = { min = 0, max = 2, hint = 'Fog thickness per world unit. 0.02 is light haze, 0.2 is thick.' },
            mode = { options = { 'Exponential', 'Linear' }, hint = 'Distance falloff of the plain fog.' },
            offset = { min = 0, hint = 'Distance from the camera where the fog starts.' },
            endDistance = {
                min = 0,
                hint = 'Distance where the Linear fog is fully opaque.',
                visibleWhen = { key = 'mode', equals = 'Linear' },
            },
            maxOpacity = { min = 0, max = 1, hint = 'Largest share of the fog colour that covers a pixel.' },
            volumetric = {
                hint = 'Ray-marched fog that shows light shafts and glowing lights. Replaces the plain fog.',
            },
            quality = {
                options = QUALITIES,
                hint = 'Low: half resolution, 16 steps. Medium: half resolution, 32 steps. High: full resolution, 48 steps and shadowed point and spot lights.',
                visibleWhen = when('volumetric'),
            },
            volumetricDistance = {
                min = 1,
                hint = 'The fog is computed up to this distance from the camera.',
                visibleWhen = when('volumetric'),
            },
            heightFalloff = {
                min = 0,
                max = 4,
                hint = 'How fast the fog thins above baseHeight. 0 = the same density at every height.',
                visibleWhen = when('volumetric'),
            },
            baseHeight = {
                hint = 'World height where the fog has full density.',
                visibleWhen = when('volumetric'),
            },
            anisotropy = {
                min = -0.95,
                max = 0.95,
                hint = 'Light scattering direction: positive brightens fog toward a light (shafts), 0 is even.',
                visibleWhen = when('volumetric'),
            },
            lightEnergy = {
                min = 0,
                max = 16,
                hint = 'Brightness of the light scattered in the fog.',
                visibleWhen = when('volumetric'),
            },
            lightClearing = {
                min = 0,
                max = 1,
                hint = 'How much point and spot lights burn the fog away where they shine (fog lamps). 0 = the fog stays as thick.',
                visibleWhen = when('volumetric'),
            },
            ambient = {
                min = 0,
                max = 4,
                hint = 'Fog light that does not depend on any light source.',
                visibleWhen = when('volumetric'),
            },
            shadows = {
                hint = 'Sunlight in the fog respects the shadow map (light shafts).',
                visibleWhen = when('volumetric'),
            },
            skyAffect = {
                min = 0,
                max = 1,
                hint = 'How much of the fog is also drawn over the sky.',
                visibleWhen = when('volumetric'),
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
        if values and section.chain ~= false and values.enabled == true then
            return true
        end
    end
    local fog = environment.fog
    if fog and fog.enabled and fog.volumetric then
        return true
    end
    return environment.render.screenSpaceAA == 'FXAA'
end

return Settings
