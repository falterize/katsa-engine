-- Readable depth of the opaque scene for SSAO and depth of field. The early depth pass already
-- produces it when it ran this frame; otherwise the batched opaque geometry is drawn depth-only.
local Prepass = require('../pipeline.depthPrepass')

local SceneDepth = {}

function SceneDepth.get(renderer)
    if renderer.depthPrepassActive and renderer.prepassDepth then
        return renderer.prepassDepth
    end
    return Prepass.renderSceneDepth(renderer)
end

return SceneDepth
