local ipairs = require('source.engine.math.array').ipairs
-- Per-voice filter: one active SoundFilter becomes a Source filter.
local Filter = {}

function Filter.apply(voice, effects)
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

return Filter
