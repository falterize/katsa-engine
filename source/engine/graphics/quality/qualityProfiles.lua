-- ribbons.detail scales Beam3D segments and Trail3D point density (nothing is removed).
-- Presets alter shared policy; atlas residency/atomic publication remain unchanged.
return {
    Low = {
        lights = { maxActiveLights = 4, nearUpdateHz = 8, farUpdateHz = 2 },
        shadows = { resolution = 128, filterSamples = 1, updateHz = 15, maxUpdateFaces = 6 },
        ribbons = { detail = 0.5 },
    },
    Medium = {
        lights = { maxActiveLights = 8, nearUpdateHz = 15, farUpdateHz = 3 },
        shadows = { resolution = 256, filterSamples = 4, updateHz = 30, maxUpdateFaces = 12 },
        ribbons = { detail = 0.75 },
    },
    High = {
        lights = { maxActiveLights = 16, nearUpdateHz = 30, farUpdateHz = 10 },
        shadows = { resolution = 512, filterSamples = 9, updateHz = 60, maxUpdateFaces = 24 },
        ribbons = { detail = 1 },
    },
}
