local V = require('../../core.validate')

-- Level selection of a LODGroup: pure functions, no nodes, no camera objects of their own.
-- A group has `levels` children (0 = most detailed). Each switch point is a threshold:
--   Distance    camera distance in world units; level k+1 starts at thresholds[k] (ascending)
--   ScreenSize  height of the group's bounding sphere as a fraction of the viewport height;
--               level k+1 starts once it falls below thresholds[k] (descending)
-- One extra threshold after the last level hides the whole group beyond it (0/absent = never).
local LodSelect = {}

LodSelect.modes = { 'Distance', 'ScreenSize' }

-- Defaults when a threshold is not given, from the size of the group (`radius`).
LodSelect.defaults = {
    distanceStart = 6, -- first switch at 6 radii from the camera
    distanceGrow = 2.5, -- each next one 2.5 times further
    screenStart = 0.3, -- first switch when the group covers less than 30% of the screen height
    screenShrink = 0.4, -- each next one at 40% of the previous
}

-- A list of numbers from a table or a comma separated text ('25, 60, 150'); other values are errors.
function LodSelect.parse(value, name)
    if value == nil or value == '' then
        return {}
    end
    local result = {}
    if type(value) == 'string' then
        for item in value:gmatch('[^,;%s]+') do
            result[#result + 1] = V.number(tonumber(item), (name or 'List') .. ' entry', 0)
        end
    else
        assert(type(value) == 'table', (name or 'List') .. ' must be a table or a text of numbers')
        for index, item in ipairs(value) do
            result[index] = V.number(item, (name or 'List') .. ' entry', 0)
        end
    end
    return result
end

-- The text form of a list (what the inspector shows and edits).
function LodSelect.format(list)
    local parts = {}
    for index, number in ipairs(list) do
        parts[index] = string.format('%.6g', number)
    end
    return table.concat(parts, ', ')
end

-- The switch points of a group with `levels` levels: the given ones where present (> 0), the
-- defaults elsewhere (levels - 1 of them), and the hide distance only when given. Sorted.
function LodSelect.thresholds(mode, levels, given, radius)
    local d = LodSelect.defaults
    local distance = mode == 'Distance'
    local result = {}
    for index = 1, levels - 1 do
        local value = given[index]
        if not value or value <= 0 then
            if distance then
                value = radius * d.distanceStart * d.distanceGrow ^ (index - 1)
            else
                value = d.screenStart * d.screenShrink ^ (index - 1)
            end
        end
        result[index] = value
    end
    if given[levels] and given[levels] > 0 then
        result[levels] = given[levels]
    end
    table.sort(result, function(a, b)
        if distance then
            return a < b
        end
        return a > b
    end)
    return result
end

-- What is compared with the thresholds. `bias` > 1 lowers the detail sooner (weak devices),
-- < 1 keeps it longer; it scales the distance up or the screen size down.
-- distance: from the camera to the group centre; pixels: height of the bounding sphere on screen.
function LodSelect.measure(mode, distance, pixels, viewportHeight, bias)
    if mode == 'Distance' then
        return distance * bias
    end
    return pixels / math.max(1, viewportHeight) / bias
end

-- 1-based index of the level a value falls on; levels + 1 means hidden. `scale` moves every
-- threshold (used for hysteresis).
local function pick(mode, value, thresholds, scale)
    local count = 0
    for _, threshold in ipairs(thresholds) do
        local limit = threshold * scale
        if mode == 'Distance' and value >= limit or mode ~= 'Distance' and value < limit then
            count = count + 1
        else
            break
        end
    end
    return count + 1
end

-- The level to show. `current` is the level shown now (nil on the first call): a coarser level
-- is taken at the threshold, a finer one only after passing it by `hysteresis` (a fraction of
-- the threshold) so a group on the border does not flicker between two levels.
function LodSelect.level(mode, value, thresholds, current, hysteresis)
    local level = pick(mode, value, thresholds, 1)
    if current and level < current and hysteresis > 0 then
        local margin = mode == 'Distance' and 1 - hysteresis or 1 + hysteresis
        level = math.min(current, math.max(level, pick(mode, value, thresholds, margin)))
    end
    return level
end

return LodSelect
