-- Resolve physical resolution/MSAA before allocation, with explicit memory caps.
local Quality = {}

function Quality.defaultSamples()
    local os = katsa.system.getOS()
    if os ~= 'Windows' and os ~= 'Linux' and os ~= 'OS X' then
        return 0
    end
    local _, _, vendor, renderer = katsa.graphics.getRendererInfo()
    -- UHD shares memory bandwidth with the CPU; retain native resolution first.
    if vendor:find('Intel', 1, true) and renderer:find('UHD', 1, true) then
        return 0
    end
    return 2
end

function Quality.defaultPixels()
    local os = katsa.system.getOS()
    return (os == 'Windows' or os == 'Linux' or os == 'OS X') and 8294400 or 4194304
end

function Quality.resolve(width, height, density, samples, limits, maxPixels, maxBytes)
    assert(density >= 0.5 and density <= 3, 'Renderer.renderDensity must be within 0.5..3')
    assert(
        samples >= 0 and samples <= 8 and samples == math.floor(samples),
        'Renderer.msaa must be an integer within 0..8'
    )
    assert(maxPixels > 0 and maxBytes > 0, 'Render allocation limits must be positive')
    density = math.min(
        density,
        math.sqrt(maxPixels / (width * height)),
        limits.texturesize / math.max(width, height)
    )
    samples = math.min(samples, limits.canvasmsaa or 0)
    local pixels = width * height * density * density
    -- Color/depth MSAA storage plus readable color resolve; driver storage varies.
    while samples > 0 and pixels * (8 * math.max(1, samples) + 4) > maxBytes do
        samples = math.floor(samples / 2)
    end
    density =
        math.min(density, math.sqrt(maxBytes / (width * height * (8 * math.max(1, samples) + 4))))
    return density, samples
end

return Quality
