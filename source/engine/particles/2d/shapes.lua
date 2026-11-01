local Shapes = {}
function Shapes.sample(e, p)
    local random, x, y = e.random, 0, 0
    if e.shape == 'Box' then
        x, y = random:random() - 0.5, random:random() - 0.5
        if e.surfaceOnly then
            local perimeter = random:random() * 2 * (e.shapeSize[1] + e.shapeSize[2])
            local w, h = e.shapeSize[1], e.shapeSize[2]
            if perimeter < w then
                x, y = (w > 0 and perimeter / w or 0) - 0.5, -0.5
            elseif perimeter < w + h then
                x, y = 0.5, (h > 0 and (perimeter - w) / h or 0) - 0.5
            elseif perimeter < 2 * w + h then
                x, y = 0.5 - (w > 0 and (perimeter - w - h) / w or 0), 0.5
            else
                x, y = -0.5, 0.5 - (h > 0 and (perimeter - 2 * w - h) / h or 0)
            end
        end
    elseif e.shape == 'Disc' then
        local angle = random:random() * math.pi * 2
        local radius = (e.surfaceOnly and 1 or math.sqrt(random:random())) / 2
        x, y = math.cos(angle) * radius, math.sin(angle) * radius
    elseif e.shape == 'Line' then
        x = random:random() - 0.5
    end
    p.x, p.y, p.z = x * e.shapeSize[1], y * e.shapeSize[2], 0
end
return Shapes
