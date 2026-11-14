-- Places both sides agree on. The lobby is where players wait; the arena is where a round is played.
local Arena = {
    lobby = { 0, 1, 0 },
    lobbyRadius = 10,
    arena = { 60, 1, 0 },
    arenaRadius = 14,
    coinCount = 10,
    limit = 120, -- no player may be farther than this from the origin
    maxSpeed = 14, -- fastest legal on-foot speed, units per second (the server's check)
}

-- A point on a circle around `center`: `fraction` 0..1 around, `scale` 0..1 from the middle.
function Arena.point(center, radius, fraction, scale)
    local angle = fraction * math.pi * 2
    return {
        center[1] + math.cos(angle) * radius * scale,
        center[2],
        center[3] + math.sin(angle) * radius * scale,
    }
end

return Arena
