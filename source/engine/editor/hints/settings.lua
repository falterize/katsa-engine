-- Inspector descriptions of the Environment settings sections (fog, glow, shadows ...) and of
-- the editor input panels.
-- Editor text only: the classes carry no hint of their own.
-- Shape: { SettingsKind = { property = 'text' } }.
local joystick = 'Safe-area logical pixels; authored values persist across resizing and are '
    .. 'clamped to the viewport.'

local hints = {
    Joystick = { x = joystick, y = joystick, radius = joystick },
    Adjustments = {
        brightness = 'Multiplies the image.',
        colorCorrection = 'Lookup-table image: a strip of N slices, N*N wide and N tall (for '
            .. 'example 256x16). Empty disables it.',
        colorCorrectionStrength = 'Mix between the original and the corrected colors.',
        contrast = 'Spreads values around middle grey.',
        saturation = '0 is greyscale, 1 unchanged.',
    },
    DepthOfField = {
        amount = 'Largest blur radius, as a share of the view height.',
        farDistance = 'Distance in world units where far blur starts.',
        farEnabled = 'Blur everything farther than farDistance.',
        farTransition = 'Distance over which far blur grows to its maximum.',
        nearEnabled = 'Blur everything closer than nearDistance.',
        quality = 'Samples per pixel: 8, 16 or 32.',
    },
    Fog = {
        ambient = 'Fog light that does not depend on any light source.',
        anisotropy = 'Light scattering direction: positive brightens fog toward a light '
            .. '(shafts), 0 is even.',
        baseHeight = 'World height where the fog has full density.',
        density = 'Fog thickness per world unit. 0.02 is light haze, 0.2 is thick.',
        heightFalloff = 'How fast the fog thins above baseHeight. 0 = the same density at every '
            .. 'height.',
        lightClearing = "Lights burn the fog away where they shine, by each light's own "
            .. 'fogClearing. Off: the fog stays as thick under every light.',
        lightEnergy = 'Brightness of the light scattered in the fog.',
        maxOpacity = 'Largest share of the fog colour that covers a pixel.',
        mode = 'Distance falloff of the plain fog.',
        offset = 'Distance from the camera where the fog starts.',
        quality = 'Low: half resolution, 16 steps. Medium: half resolution, 32 steps. High: '
            .. 'full resolution, 48 steps and shadowed point and spot lights.',
        shadows = 'Sunlight in the fog respects the shadow map (light shafts).',
        skyAffect = 'How much of the fog is also drawn over the sky.',
        volumetric = 'Ray-marched fog that shows light shafts and glowing lights. Replaces the '
            .. 'plain fog.',
        volumetricDistance = 'The fog is computed up to this distance from the camera.',
    },
    Glow = {
        blendMode = 'How the glow combines with the image.',
        bloom = 'Glow added from every pixel, not only the bright ones.',
        hdrScale = 'Glow multiplier applied to the part above the threshold.',
        hdrThreshold = 'Luminance above which pixels glow. Measured after tone mapping, 0..1.',
        intensity = 'Glow amount added to the image.',
        levels = 'Blur levels: more is wider.',
        strength = 'Blur spread: larger values widen the glow.',
    },
    PhysicsDebug = {
        wireframe = 'Draw physics shapes as wire geometry. Does not change the main material '
            .. 'renderer.',
    },
    SSAO = {
        intensity = 'Darkening strength.',
        power = 'Contrast of the darkening falloff.',
        quality = 'Samples per pixel: 8, 12 or 20.',
        radius = 'Occlusion search radius in world units.',
    },
    Shadows = {
        blockerSearchRadius = 'Blocker-search radius in atlas pixels; 9 fixed taps.',
        filterSamples = 'Standard PCF taps; Realistic uses fixed 9 blocker + 9 filter taps.',
        lightSize = 'Approximate relative emitter size for contact-hardening shadows.',
        softnessLimit = 'Maximum PCF filter radius in atlas pixels.',
    },
    Sky = {
        pixelate = 'Nearest sampling for this sky only; false uses linear smoothing.',
        texture = 'Project-relative sky image path or registered image name. Cross requires a '
            .. '4:3 image.',
        yaw = 'Sky rotation around the world Y axis, in degrees.',
    },
}

-- A World2D Environment has the same Adjustments without the colour-correction table.
hints.Adjustments2D = {
    brightness = hints.Adjustments.brightness,
    contrast = hints.Adjustments.contrast,
    saturation = hints.Adjustments.saturation,
}

return hints
