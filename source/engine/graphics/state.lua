local ipairs = require('source.engine.math.array').ipairs

local State = {}

function State.restoreUIStencil(ui)
    if not ui._stencilLevel or ui._stencilLevel == 0 then
        return
    end
    local g = love.graphics
    g.push('all')
    g.setScissor()
    g.setShader()
    g.setStencilTest()
    g.stencil(ui._clearStencil, 'replace', 0, false)
    for _, ancestor in ipairs(ui._stencilStack or {}) do
        ui._stencilNode = ancestor
        g.stencil(ui._stencilRectangle, 'increment', 1, true)
    end
    g.pop()
end

function State.reapplyScissor()
    local g = love.graphics
    local x, y, w, h = g.getScissor()
    g.setScissor()
    if x then
        g.setScissor(x, y, w, h)
    end
end

return State
