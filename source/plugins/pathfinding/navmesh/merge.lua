-- Greedy rectangle merging: the free cells of one tile and level become few large convex
-- polygons. A rectangle only joins cells of similar height (`flatness`), so each polygon is a
-- near-planar patch and the path through it is a straight line.
local Merge = {}

-- Calls emit(cx0, cz0, cx1, cz1) for every rectangle. `free(cx, cz)` says whether a cell can be
-- part of one; `heightOf(cx, cz)` its surface height. `kindOf(cx, cz)` (optional) is compared with
-- ==: a rectangle never mixes kinds (navigation areas). Cells are visited row by row.
function Merge.tile(cx0, cz0, cx1, cz1, free, heightOf, flatness, emit, kindOf)
    local taken = {}
    local width = cx1 - cx0 + 1
    local function key(cx, cz)
        return (cz - cz0) * width + (cx - cx0) + 1
    end
    for cz = cz0, cz1 do
        for cx = cx0, cx1 do
            if free(cx, cz) and not taken[key(cx, cz)] then
                local base = heightOf(cx, cz)
                local kind = kindOf and kindOf(cx, cz)
                local function fits(x, z)
                    return x <= cx1
                        and z <= cz1
                        and free(x, z)
                        and not taken[key(x, z)]
                        and math.abs(heightOf(x, z) - base) <= flatness
                        and (not kindOf or kindOf(x, z) == kind)
                end
                local right = cx
                while fits(right + 1, cz) do
                    right = right + 1
                end
                local bottom = cz
                while true do
                    local row = true
                    for x = cx, right do
                        if not fits(x, bottom + 1) then
                            row = false
                            break
                        end
                    end
                    if not row then
                        break
                    end
                    bottom = bottom + 1
                end
                for z = cz, bottom do
                    for x = cx, right do
                        taken[key(x, z)] = true
                    end
                end
                emit(cx, cz, right, bottom)
            end
        end
    end
end

return Merge
