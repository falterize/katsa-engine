local ipairs = require('source.engine.math.array').ipairs
-- Two exact 16-bit halves avoid per-fragment palette decoding and indirect light loads.
local Masks = {}

local function pack(list)
    local low, high = 0, 0
    for _, index in ipairs(list) do
        if index <= 16 then
            low = low + 2 ^ (index - 1)
        else
            high = high + 2 ^ (index - 17)
        end
    end
    return { low, high }
end
local all = {}
for i = 1, 32 do
    all[i] = i
end
Masks.all = pack(all)

function Masks.update(objects, lights)
    local snapshot = lights._membershipSnapshot or {}
    lights._membershipSnapshot = snapshot
    local changed = snapshot.count ~= lights.count
    snapshot.count = lights.count
    for i = 1, lights.count do
        local p = lights.position[i]
        local old = snapshot[i] or {}
        snapshot[i] = old
        for j = 1, 4 do
            if old[j] ~= p[j] then
                changed = true
                old[j] = p[j]
            end
        end
    end
    if Masks.forceAll then
        for _, object in ipairs(objects) do
            object._lightPalette = Masks.all
            object._lightPaletteState = nil
        end
        return
    end
    if changed then
        lights._membershipRevision = (lights._membershipRevision or 0) + 1
    end
    for _, object in ipairs(objects) do
        local p = object.worldPosition or object.position
        local radius = object.radius + (object._shaderBoundsPadding or 0)
        local state = object._lightPaletteState
        if
            not state
            or state[1] ~= p[1]
            or state[2] ~= p[2]
            or state[3] ~= p[3]
            or state[4] ~= radius
            or state[5] ~= lights._membershipRevision
            or state[6] ~= object._shaderBoundsUnknown
        then
            state = state or {}
            object._lightPaletteState = state
            state[1], state[2], state[3], state[4], state[5], state[6] =
                p[1], p[2], p[3], radius, lights._membershipRevision, object._shaderBoundsUnknown
            if object._shaderBoundsUnknown then
                object._lightPalette = Masks.all
            else
                local low, high = 0, 0
                for i = 1, lights.count do
                    local light = lights.position[i]
                    if
                        light[4] == 0
                        or (p[1] - light[1]) ^ 2 + (p[2] - light[2]) ^ 2 + (p[3] - light[3]) ^ 2
                            <= (light[4] + radius) ^ 2
                    then
                        if i <= 16 then
                            low = low + 2 ^ (i - 1)
                        else
                            high = high + 2 ^ (i - 17)
                        end
                    end
                end
                local palette = object._lightPalette
                if not palette or palette == Masks.all then
                    palette = {}
                end
                palette[1], palette[2] = low, high
                object._lightPalette = palette
            end
        end
    end
end

return Masks
