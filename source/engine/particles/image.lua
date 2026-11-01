local Image = require('source.engine.components.image')
local Policy = {}
function Policy.initialize(node)
    node.imageMode = node.imageMode or (node.atlasEnabled and 'Atlas' or 'Decal')
    Image.initialize(node)
end

function Policy.uv(node, p, image, size)
    local frame = node.atlasFrame or 0
    local mode = node.imageMode
    if node.atlasEnabled and mode == 'Decal' then
        mode = 'Atlas'
    end
    if mode == 'Atlas' or mode == 'XML' then
        if mode == 'XML' and node._xmlBinding then
            local definition = node._xmlBinding.definition
            local clip =
                definition.clips[node.atlasAnimation ~= '' and node.atlasAnimation or definition.initial]
            if clip then
                local index = math.floor(p.age * clip.fps)
                index = clip.loop and index % #clip.frames or math.min(#clip.frames - 1, index)
                frame = clip.frames[index + 1]
            end
        elseif node.atlasEnabled then
            local count = node.atlasGrid[1] * node.atlasGrid[2]
            frame = math.floor(p.age * node.atlasFPS)
            frame = node.atlasLoop and frame % count or math.min(count - 1, frame)
        end
    end
    local iw, ih = image:getDimensions()
    local x, y, w, h = Image.uv(node, iw, ih, size, size, frame, mode)
    return x, y, w, h
end
return Policy
