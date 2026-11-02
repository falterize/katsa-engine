local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Cached EFX definitions: collects node properties and (re)defines the driver effect.
local Definition = {}
local keys = {
    'volume',
    'gain',
    'gainhf',
    'density',
    'diffusion',
    'decaytime',
    'decayhfratio',
    'reflectionsdelay',
    'reflectionsgain',
    'latedelay',
    'lategain',
    'airabsorptiongainhf',
    'roomrollofffactor',
    'decayhflimit',
    'delay',
    'tapdelay',
    'damping',
    'feedback',
    'spread',
    'waveform',
    'rate',
    'depth',
    'phase',
    'edge',
    'lowcut',
    'center',
    'bandwidth',
}

local function supported(audio)
    if audio.effectsSupported == nil then
        local ok, value = pcall(katsa.audio.isEffectsSupported)
        audio.effectsSupported = ok and value or false
        local success, limit = pcall(katsa.audio.getMaxSourceEffects)
        audio.maxSourceEffects = success and limit or 0
    end
    return audio.effectsSupported
end

local function wetMuted(audio, node)
    if audio.paused or node._wetMuted then
        return true
    end
    local owner = node.parent
    while owner do
        if owner:isA('Sound') and owner.enabled == false then
            return true
        end
        if owner:isA('SoundGroup') and (owner.muted or owner.volume == 0) then
            return true
        end
        owner = owner.parent
    end
    return false
end

function Definition.define(audio, node)
    if not supported(audio) then
        node.status = 'Unsupported on this device'
        return false
    end
    local values = node._effectValues or {}
    node._effectValues = values
    local settings = node._effectSettings or {}
    node._effectSettings = settings
    settings.type = node.effectType
    local changed = not node._attempted
    for _, key in ipairs(keys) do
        local value = node[key]
        if key == 'volume' and wetMuted(audio, node) then
            value = 0
        end
        if values[key] ~= value then
            changed = true
            values[key] = value
        end
        settings[key] = value
    end
    if changed then
        local ok, result = pcall(katsa.audio.setEffect, node._effectName, settings)
        node._attempted = true
        node._defined = ok and result == true
        node.status = node._defined and 'Ready' or ('Unavailable: ' .. tostring(result))
    end
    return node._defined == true
end


return Definition
