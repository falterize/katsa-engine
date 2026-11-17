-- The memory of a Shader2D that declares `uniform sampler2D previous : hint_history_texture;`:
-- its own result from the previous frame, as it was drawn. A shader that feeds this back (a trail,
-- a datamosh smear, temporal smoothing) reads it with the same uv as the screen texture. The canvas
-- is made on first use, the first frame sees the unprocessed picture, and a shader without the hint
-- pays nothing.
local EffectHistory = {}

local function reset(g)
    g.origin()
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.setDepthMode()
    g.setStencilTest()
end

-- The canvas holding last frame's result; `snapshot` seeds it when it is new or the size changed.
function EffectHistory.get(node, snapshot)
    local g = katsa.graphics
    local w, h = snapshot:getDimensions()
    local history = node._effectHistory
    if not history or history:getWidth() ~= w or history:getHeight() ~= h then
        if history then
            history:release()
        end
        history = g.newCanvas(w, h, { dpiscale = snapshot:getDPIScale() })
        history:setFilter('linear', 'linear')
        node._effectHistory = node:own(history)
        g.push('all')
        g.setCanvas(history)
        reset(g)
        g.setScissor()
        g.setBlendMode('replace', 'premultiplied')
        g.draw(snapshot)
        g.pop()
    end
    return history
end

-- Keeps the rectangle of `scene` (where the effect just drew its result) for the next frame.
function EffectHistory.store(node, scene, x, y, width, height)
    local history = node._effectHistory
    if not history then
        return
    end
    local g = katsa.graphics
    g.push('all')
    g.setCanvas(history)
    reset(g)
    g.setBlendMode('replace', 'premultiplied')
    g.setScissor(x, y, width, height)
    g.draw(scene)
    g.pop()
end

return EffectHistory
