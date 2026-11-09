-- Finds the places agents of this scene can jump between and adds them to the NavMap3D as
-- 'jump' links. This is scene logic on purpose: the plugin only routes and hands the action over,
-- so a game decides here what counts as jumpable (height, distance, which edges).
--
-- From every walkable cell next to a blocked one, a straight line (the four axes) is followed over
-- the blocked cells to the first walkable cell. The pair becomes a link when something really
-- needs a jump there (a step higher than `maxStep`, a pit or an obstacle) and the obstacle in
-- between is no higher than `maxJump` above the take-off, the landing is at most `maxJump` higher
-- and at most `maxDrop` lower, and the gap is at most `distance` units wide.
local JumpLinks = {}

local DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function JumpLinks.generate(map, options)
    options = options or {}
    local maxJump, maxDrop = options.maxJump or 1.2, options.maxDrop or 4
    local maxStep = options.maxStep or map.maxStep
    local mesh = map:getMesh()
    local reach = math.floor((options.distance or 6) / mesh.cellSize)
    -- One link per `spacing` cells along an edge keeps the link count (and the debug view) sane.
    local spacing = options.spacing or 1
    local count = 0
    for level = 1, mesh.levels do
        local blocked, heights = mesh.blocked[level], mesh.heights[level]
        for cz = 1, mesh.depth do
            for cx = 1, mesh.width do
                local index = mesh:index(cx, cz)
                local from = heights[index]
                if from and not blocked[index] then
                    for _, dir in ipairs(DIRECTIONS) do
                        local peak, pit = -math.huge, false
                        for k = 1, reach do
                            local nx, nz = cx + dir[1] * k, cz + dir[2] * k
                            if not mesh:inside(nx, nz) then
                                break
                            end
                            local other = mesh:index(nx, nz)
                            local to = heights[other]
                            if blocked[other] or not to then
                                peak = math.max(peak, to or -math.huge)
                                pit = pit or not to
                            else
                                local gap = to - from
                                local both = gap <= maxJump and -gap <= maxJump
                                -- Both ways: add once (from the lower index). One way: add from here.
                                if
                                    k > 1
                                    and (dir[1] ~= 0 and cz or cx) % spacing == 0
                                    and peak - from <= maxJump
                                    and gap <= maxJump
                                    and -gap <= maxDrop
                                    and (not both or index < other)
                                    -- Something to jump: a step too high to walk, an obstacle
                                    -- or a pit in between (not just cells blocked by the agent margin).
                                    and (math.abs(gap) > maxStep or pit or peak > math.max(from, to) + 0.3)
                                then
                                    local ax, az = mesh:toWorld(cx, cz)
                                    local bx, bz = mesh:toWorld(nx, nz)
                                    mesh:addLink({
                                        level = level,
                                        ax = ax,
                                        az = az,
                                        bx = bx,
                                        bz = bz,
                                        action = 'jump',
                                        bidirectional = both,
                                        arcHeight = 1,
                                        auto = true,
                                        -- The highest obstacle top between the two cells: the arc must clear it.
                                        data = { peak = peak },
                                    })
                                    count = count + 1
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    return count
end

return JumpLinks
