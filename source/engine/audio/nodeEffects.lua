local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Cached EFX definitions and per-voice routing. OpenAL effects are parallel sends.
local Routing = {}
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

function Routing.define(audio, node)
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

function Routing.apply(audio, sound, voice, effects)
    local wanted = voice._wantedEffects or {}
    voice._wantedEffects = wanted
    for key in pairs(wanted) do
        wanted[key] = nil
    end
    local count = 0
    for _, effect in ipairs(effects) do
        if
            sound.enabled
            and effect.effectType ~= 'pitch'
            and effect.effectType ~= 'filter'
            and effect.enabled
            and not effect.destroyed
        then
            if Routing.define(audio, effect) then
                if count < (audio.maxSourceEffects or 0) then
                    wanted[effect._effectName] = effect
                    count = count + 1
                else
                    effect.status = 'Source effect limit reached'
                end
            end
        end
    end
    voice._appliedEffects = voice._appliedEffects or {}
    local applied = voice._appliedEffects
    for name in pairs(applied) do
        if not wanted[name] then
            for _, source in ipairs(voice.sources) do
                pcall(source.setEffect, source, name, false)
            end
            applied[name] = nil
        end
    end
    for name, effect in pairs(wanted) do
        if applied[name] == nil then
            local success = true
            for _, source in ipairs(voice.sources) do
                local ok, value = pcall(source.setEffect, source, name, true)
                success = success and ok and value == true
            end
            applied[name] = success
        end
        effect.status = applied[name] and 'Applied' or 'Source rejected effect'
    end
    local filter
    for _, effect in ipairs(effects) do
        if effect.enabled and effect.effectType == 'filter' then
            filter = effect
        end
    end
    local signature = filter
            and table.concat(
                { filter.filterType, filter.volume, filter.lowgain, filter.highgain },
                ':'
            )
        or 'none'
    if signature ~= voice._filterSignature then
        for _, source in ipairs(voice.sources) do
            local ok, value
            if filter then
                local settings = {
                    type = filter.filterType,
                    volume = filter.volume,
                }
                if filter.filterType ~= 'lowpass' then
                    settings.lowgain = filter.lowgain
                end
                if filter.filterType ~= 'highpass' then
                    settings.highgain = filter.highgain
                end
                ok, value = pcall(source.setFilter, source, settings)
            else
                ok, value = pcall(source.setFilter, source)
            end
            if filter then
                filter.status = ok and value ~= false and 'Applied'
                    or ('Filter unavailable: ' .. tostring(value))
            end
        end
        voice._filterSignature = signature
    end
end

function Routing.remove(audio, node)
    for _, voice in ipairs(audio.voices) do
        if voice._appliedEffects and voice._appliedEffects[node._effectName] then
            for _, source in ipairs(voice.sources) do
                pcall(source.setEffect, source, node._effectName, false)
            end
            voice._appliedEffects[node._effectName] = nil
        end
    end
    if node._defined then
        pcall(katsa.audio.setEffect, node._effectName, false)
        node._defined = false
    end
    node._attempted = false
    node.status = 'Not applied'
end

return Routing
