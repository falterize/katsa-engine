-- Remembers finished decompositions. Many colliders share one model (a field of identical cars),
-- and a decomposition costs tens of milliseconds, so the result is keyed by a fingerprint of the
-- exact triangle data plus the settings and reused. The cache is bounded (oldest entries go first).
local Cache = {}

local LIMIT = 64
local entries, order = {}, {}

-- A 47-bit style fingerprint of a vertex list; vertices are compared to a micrometre.
function Cache.fingerprint(vertices)
    local a, b = 5381, 52711
    for i = 1, #vertices do
        local v = vertices[i]
        for axis = 1, 3 do
            local n = math.floor(v[axis] * 1e6 + 0.5) % 4294967291
            a = (a * 33 + n) % 140737488355213
            b = (b * 131 + n + axis) % 140737488355213
        end
    end
    return string.format('%d:%x:%x', #vertices, a, b)
end

function Cache.get(key)
    return entries[key]
end

function Cache.put(key, value)
    if not entries[key] then
        order[#order + 1] = key
        if #order > LIMIT then
            entries[table.remove(order, 1)] = nil
        end
    end
    entries[key] = value
    return value
end

function Cache.clear()
    entries, order = {}, {}
end

return Cache
