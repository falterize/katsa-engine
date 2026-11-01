-- Shape size is the full local extent; sphere/disc use independent axis extents.
local S = {}

function S.sample(e, p)
    local random = e.random
    local size = e.shapeSize
    local shape = e.shape
    local x, y, z = 0, 0, 0
    if shape == 'Box' then
        x, y, z = random:random() - 0.5, random:random() - 0.5, random:random() - 0.5
        if e.surfaceOnly then
            local axis = random:random(1, 3)
            local side = random:random() < 0.5 and -0.5 or 0.5
            if axis == 1 then
                x = side
            elseif axis == 2 then
                y = side
            else
                z = side
            end
        end
    elseif shape == 'Sphere' then
        local up = random:random() * 2 - 1
        local a = random:random() * math.pi * 2
        local r = (e.surfaceOnly and 1 or random:random() ^ (1 / 3)) * 0.5
        local h = math.sqrt(1 - up * up)
        x, y, z = math.cos(a) * h * r, up * r, math.sin(a) * h * r
    elseif shape == 'Disc' or shape == 'Cylinder' then
        local a = random:random() * math.pi * 2
        local r = (e.surfaceOnly and 1 or math.sqrt(random:random())) * 0.5
        x, z = math.cos(a) * r, math.sin(a) * r
        y = shape == 'Cylinder' and random:random() - 0.5 or 0
    end
    p.x, p.y, p.z = x * size[1], y * size[2], z * size[3]
end

return S
