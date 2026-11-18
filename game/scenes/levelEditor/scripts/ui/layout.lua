-- Dock geometry of the editor window (pure Lua): a toolbar on top, a status bar at the bottom,
-- a left and a right dock over the full middle height and a bottom dock under the viewport,
-- like the Godot editor. Splitter sizes are clamped so the viewport never collapses, from
-- 1280x720 down to small windows.
local Layout = {}

Layout.SPLIT = 5
Layout.MIN = { left = 170, right = 230, bottom = 90 }
Layout.MIN_VIEW = { width = 300, height = 160 }
Layout.DEFAULTS = { left = 250, right = 320, bottom = 190 }

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Returns a clamped copy of `sizes` ({ left, right, bottom }) for a window.
function Layout.clamp(sizes, width, height, top, status)
    local result = {
        left = math.max(Layout.MIN.left, sizes.left or Layout.DEFAULTS.left),
        right = math.max(Layout.MIN.right, sizes.right or Layout.DEFAULTS.right),
        bottom = math.max(Layout.MIN.bottom, sizes.bottom or Layout.DEFAULTS.bottom),
    }
    local free = width - 2 * Layout.SPLIT - Layout.MIN_VIEW.width
    if result.left + result.right > free then
        local factor = math.max(0, free) / (result.left + result.right)
        result.left = math.max(Layout.MIN.left, math.floor(result.left * factor))
        result.right = math.max(Layout.MIN.right, math.floor(result.right * factor))
        if result.left + result.right > free then
            -- A very small window: share what is left, the docks may go below their minimum.
            result.left = math.max(60, math.floor(free * 0.45))
            result.right = math.max(60, free - result.left)
        end
    end
    local room = height - top - status - Layout.SPLIT - Layout.MIN_VIEW.height
    result.bottom = clamp(result.bottom, math.min(Layout.MIN.bottom, math.max(40, room)), math.max(40, room))
    return result
end

local function rect(x, y, w, h)
    return { x = x, y = y, w = math.max(0, w), h = math.max(0, h) }
end

-- Every rectangle in window units. `sizes` are clamped first (the clamped copy is `sizes`).
function Layout.compute(width, height, sizes, top, status)
    sizes = Layout.clamp(sizes, width, height, top, status)
    local split = Layout.SPLIT
    local middle = height - top - status
    local centerX = sizes.left + split
    local centerW = width - sizes.left - sizes.right - 2 * split
    local viewH = middle - sizes.bottom - split
    return {
        sizes = sizes,
        top = rect(0, 0, width, top),
        status = rect(0, height - status, width, status),
        left = rect(0, top, sizes.left, middle),
        right = rect(width - sizes.right, top, sizes.right, middle),
        view = rect(centerX, top, centerW, viewH),
        bottom = rect(centerX, top + middle - sizes.bottom, centerW, sizes.bottom),
        splitLeft = rect(sizes.left, top, split, middle),
        splitRight = rect(width - sizes.right - split, top, split, middle),
        splitBottom = rect(centerX, top + viewH, centerW, split),
    }
end

return Layout
