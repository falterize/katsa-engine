local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Per-voice effect routing. OpenAL effects are parallel sends.
local Definition = require('./definition')
local Filter = require('./filter')
local Routing = {}

Routing.define = Definition.define

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
            if Definition.define(audio, effect) then
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
    Filter.apply(voice, effects)
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
