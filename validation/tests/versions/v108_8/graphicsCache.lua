-- GL state cache truthfulness: deleting a mesh whose index buffer is bound must clear the cached
-- element-buffer binding (a stale cache made the next mesh that reused the id draw from address 0).
local Core = require('source.katsa.graphics.core')

local Module = {}

function Module.run(self)
    local g = katsa.graphics
    local canvas = g.newCanvas(16, 16, { dpiscale = 1 })
    g.setCanvas(canvas)
    local mesh = g.newMesh(4, 'triangles', 'stream')
    mesh:setVertexMap({ 1, 2, 3 })
    g.draw(mesh)
    g.flushBatch()
    local bound = Core.boundElementBuffer
    mesh:release()
    self:check(
        bound ~= nil and Core.boundElementBuffer ~= bound,
        'Releasing a mesh forgets its cached element buffer binding'
    )
    local next = g.newMesh(4, 'triangles', 'stream')
    next:setVertexMap({ 1, 2, 3 })
    g.draw(next)
    g.flushBatch()
    g.setCanvas()
    self:check(Core.boundElementBuffer ~= nil, 'A new mesh binds its own index buffer after the old one was released')
    next:release()
    canvas:release()
end

return Module
