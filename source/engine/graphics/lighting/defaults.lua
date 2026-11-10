local Defaults = {}

function Defaults.create()
    local gizmos = { enabled = true, updateHz = 8, activeOnly = true, maxDistance = 0 }
    return {
        ambient = { 65, 70, 80 },
        toneMapping = true,
        exposure = 1,
        shadows = {
            mode = 'Standard',
            lightSize = 0.04,
            softnessLimit = 8,
            blockerSearchRadius = 4,
            enabled = false,
            resolution = 256,
            distance = 240,
            fadeDistance = 24,
            sourceFadeSeconds = 0.15,
            maxUpdateFaces = 12,
            visibleFacesOnly = true,
            near = 0.5,
            updateHz = 60,
            bias = 0.02,
            normalBias = 0.5,
            strength = 0.9,
            filterSamples = 1,

            layers = -1,
        },
        lightSettings = {
            maxActiveLights = 12,
            selectionHz = 5,
            nearDistance = 100,
            nearUpdateHz = 15,
            farUpdateHz = 3,
            selectionBias = 0.1,
            selectionHoldSeconds = 0.4,
            cullInvisible = true,
        },
        debug = {
            bones = false,
            wireframe = false,
            gizmos = gizmos,
            orientation2D = false,
            orientation3D = false,
        },
        gizmos = gizmos, -- Previous API shares the canonical debug settings.
        sky = {
            enabled = true,
            texture = 'assets/textures/sky/dayCross.png',
            pixelate = false,
            _settingsKind = 'Sky',
            color = { 255, 255, 255 },
            brightness = 1,
            layout = 'Cross',
            yaw = 0,
        },
        fog = {
            enabled = true,
            color = { 160, 185, 210 },
            density = 0.006,
            offset = 80,
            maxOpacity = 0.9,
            mode = 'Exponential',
            endDistance = 450,
        },
    }
end

return Defaults
