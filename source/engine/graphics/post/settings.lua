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
            intensity = { min = 0, max = 8 },
            strength = { min = 0, max = 2 },
            mix = {
                min = 0,
                max = 1,
                visibleWhen = { key = 'blendMode', equals = 'Mix' },
            },
            bloom = {
                min = 0,
                max = 1,
            },
            blendMode = { options = BLEND_MODES },
            hdrThreshold = {
                min = 0,
                max = 4,
            },
            hdrScale = {
                min = 0,
                max = 8,
            },
            levels = { min = 1, max = 7, integer = true },
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
            quality = { options = QUALITIES },
            radius = { min = 0.01, max = 50 },
            intensity = { min = 0, max = 16 },
            power = { min = 0.1, max = 8 },
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
            lightClearing = true,
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
            density = { min = 0, max = 2 },
            mode = { options = { 'Exponential', 'Linear' } },
            offset = { min = 0 },
            endDistance = {
                min = 0,
                visibleWhen = { key = 'mode', equals = 'Linear' },
            },
            maxOpacity = { min = 0, max = 1 },
            volumetric = {},
            quality = {
                options = QUALITIES,
                visibleWhen = when('volumetric'),
            },
            volumetricDistance = {
                min = 1,
                visibleWhen = when('volumetric'),
            },
            heightFalloff = {
                min = 0,
                max = 4,
                visibleWhen = when('volumetric'),
            },
            baseHeight = {
                visibleWhen = when('volumetric'),
            },
            anisotropy = {
                min = -0.95,
                max = 0.95,
                visibleWhen = when('volumetric'),
            },
            lightEnergy = {
                min = 0,
                max = 16,
                visibleWhen = when('volumetric'),
            },
            lightClearing = {
                visibleWhen = when('volumetric'),
            },
            ambient = {
                min = 0,
                max = 4,
                visibleWhen = when('volumetric'),
            },
            shadows = {
                visibleWhen = when('volumetric'),
            },
            skyAffect = {
                min = 0,
                max = 1,
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
            farEnabled = {},
            farDistance = {
                min = 0,
                visibleWhen = when('farEnabled'),
            },
            farTransition = {
                min = 0.001,
                visibleWhen = when('farEnabled'),
            },
            nearEnabled = {},
            nearDistance = {
                min = 0,
                visibleWhen = when('nearEnabled'),
            },
            nearTransition = {
                min = 0.001,
                visibleWhen = when('nearEnabled'),
            },
            amount = { min = 0, max = 1 },
            quality = { options = QUALITIES },
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
            brightness = { min = 0, max = 8 },
            contrast = { min = 0, max = 8 },
            saturation = { min = 0, max = 8 },
            colorCorrection = {},
            colorCorrectionStrength = {
                min = 0,
                max = 1,
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

-- A World2D Environment has the Adjustments too, without the colour-correction table: the UI
-- compositor applies them to the finished picture of the plane.
local adjustments3D = byKind.Adjustments
Settings.sections2D = {
    {
        field = 'adjustments',
        title = 'Adjustments',
        kind = 'Adjustments2D',
        defaults = { enabled = false, brightness = 1.0, contrast = 1.0, saturation = 1.0 },
        keys = { 'enabled', 'brightness', 'contrast', 'saturation' },
        descriptors = adjustments3D.descriptors,
    },
}
byKind.Adjustments2D = Settings.sections2D[1]

function Settings.definition(kind)
    return byKind[kind]
end

-- Adds every missing section (and missing key of a section) to an Environment.
local function installSections(environment, sections)
    for _, section in ipairs(sections) do
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
end

function Settings.install2D(environment)
    installSections(environment, Settings.sections2D)
end

function Settings.install(environment)
    installSections(environment, Settings.sections)
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
