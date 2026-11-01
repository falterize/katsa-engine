-- Archived scenes keep their original engine imports; implementation stays categorized.
local Imports = {}

function Imports.resolve(name)
    local prefix = 'source.engine.physics.'
    if name:sub(1, #prefix) == prefix then
        local suffix = name:sub(#prefix + 1)
        if
            suffix ~= '2d'
            and suffix ~= '3d'
            and suffix:sub(1, 3) ~= '2d.'
            and suffix:sub(1, 3) ~= '3d.'
        then
            return prefix .. '3d.' .. suffix
        end
    end
    local nodes = 'source.engine.nodes.physics.'
    if name:sub(1, #nodes) == nodes then
        local suffix = name:sub(#nodes + 1)
        if suffix == 'body3D' or suffix == 'collider3D' or suffix == 'constraints' then
            return nodes .. '3d.' .. suffix
        end
    end
    return name
end

return Imports
