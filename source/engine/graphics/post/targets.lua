-- Canvas pool of the post chain. Every canvas keeps the logical size of the scene canvas, so
-- one `g.draw(canvas)` always covers the whole target; `divisor` only lowers the pixel count
-- (dpiscale / divisor). Targets are rebuilt when the scene canvas changes size or density.
local Targets = {}

local function release(pool)
    for key, canvas in pairs(pool.canvases) do
        canvas:release()
        pool.canvases[key] = nil
    end
end

function Targets.new()
    return { canvases = {}, width = 0, height = 0, density = 0 }
end

-- A canvas of `format` at 1/divisor of the scene resolution, created on first use.
function Targets.get(pool, renderer, name, divisor, format)
    local width, height, density = renderer.width, renderer.height, renderer.density
    if pool.width ~= width or pool.height ~= height or pool.density ~= density then
        release(pool)
        pool.width, pool.height, pool.density = width, height, density
    end
    local key = name .. ':' .. divisor
    local canvas = pool.canvases[key]
    if not canvas then
        canvas = katsa.graphics.newCanvas(width, height, {
            format = format or 'rgba8',
            dpiscale = density / divisor,
        })
        canvas:setFilter('linear', 'linear')
        pool.canvases[key] = canvas
    end
    return canvas
end

Targets.release = release

return Targets
