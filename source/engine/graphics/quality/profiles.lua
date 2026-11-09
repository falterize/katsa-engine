-- Quality profiles trade GPU/CPU cost for fidelity without removing any feature:
-- a profile only changes numeric settings of Environment.rendering, Environment.shadows and the
-- sample counts of the post-processing effects.
local Profiles = {}

Profiles.names = { 'Low', 'Medium', 'High' }

-- resolutionCap limits (never raises) the shadow map size a scene authored.
local definitions = {
    Low = {
        render = { renderDensity = 0.75, msaa = 0 },
        post = { ssaoQuality = 'Low', dofQuality = 'Low', glowLevels = 4 },
        shadows = {
            resolutionCap = 512,
            distance = 120,
            updateHz = 20,
            filterSamples = 1,
            maxUpdateFaces = 3,
        },
    },
    Medium = {
        render = { renderDensity = 1, msaa = 0 },
        post = { ssaoQuality = 'Medium', dofQuality = 'Medium', glowLevels = 5 },
        shadows = {
            resolutionCap = 1024,
            distance = 180,
            updateHz = 30,
            filterSamples = 1,
            maxUpdateFaces = 6,
        },
    },
    High = {
        render = { renderDensity = 1, msaa = 2 },
        post = { ssaoQuality = 'High', dofQuality = 'High', glowLevels = 6 },
        shadows = {
            resolutionCap = 4096,
            distance = 240,
            updateHz = 60,
            filterSamples = 4,
            maxUpdateFaces = 12,
        },
    },
}

-- Suggests a profile for the current GPU; scenes and users decide whether to apply it.
function Profiles.recommended()
    local _, _, vendor, renderer = katsa.graphics.getRendererInfo()
    if vendor:find('Intel', 1, true) and renderer:find('UHD', 1, true) then
        return 'Low'
    end
    return 'High'
end

function Profiles.apply(environment, name)
    local profile = definitions[name]
    assert(profile, 'Unknown quality profile: ' .. tostring(name))
    for key, value in pairs(profile.render) do
        environment.render[key] = value
    end
    -- Post-processing keeps every effect and only lowers its sample counts.
    environment.ssao.quality = profile.post.ssaoQuality
    environment.depthOfField.quality = profile.post.dofQuality
    environment.glow.levels = profile.post.glowLevels
    local shadows = environment.shadows
    for key, value in pairs(profile.shadows) do
        if key == 'resolutionCap' then
            shadows.resolution = math.min(shadows.resolution, value)
        else
            shadows[key] = value
        end
    end
    return name
end

function Profiles.next(name)
    for index, candidate in ipairs(Profiles.names) do
        if candidate == name then
            return Profiles.names[index % #Profiles.names + 1]
        end
    end
    return Profiles.names[1]
end

return Profiles
