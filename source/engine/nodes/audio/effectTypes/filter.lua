-- Filter: per-voice low/high/band pass.
return {
    name = 'SoundFilter',
    effectType = 'filter',
    category = 'tone',
    defaults = {
    filterType = 'lowpass',
    highgain = 0.15,
    lowgain = 1,
    },
}
