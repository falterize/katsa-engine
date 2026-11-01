local Clock = {}

function Clock.delta(root, dt)
    local scale = root.timeScale
    assert(
        type(scale) == 'number' and scale == scale and scale >= 0 and scale <= 100,
        'World TimeScale must be within 0..100'
    )
    return dt * scale
end

return Clock
