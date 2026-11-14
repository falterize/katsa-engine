local ffi = require('ffi')
local Textures = require('./textures')

-- Draws ImGui's draw data with katsa.graphics meshes, so the GL state cache stays truthful (no
-- raw GL calls). One mesh per draw list, grown on demand: ImDrawVert (pos, uv, rgba bytes) is
-- exactly the default katsa vertex format, and ImDrawIdx is a 16-bit index.
local Renderer = {}
Renderer.__index = Renderer

-- Set by Renderer.new: the cdef is declared when the library loads, not when this file does.
local VERTEX_BYTES
local INDEX_BYTES = 2

-- A raw-memory block as the mesh API wants it: getPointer / getSize.
local function newView()
    local block = { pointer = nil, size = 0 }
    function block.getPointer()
        return block.pointer
    end
    function block.getSize()
        return block.size
    end
    return block
end

local function point(block, pointer, size)
    block.pointer, block.size = pointer, size
    return block
end

function Renderer.new(C)
    VERTEX_BYTES = ffi.sizeof('ImDrawVert')
    return setmetatable({
        C = C,
        textures = Textures.new(C),
        meshes = {},
        -- Raw-memory views handed to Mesh:setVertices / setVertexMap without copying into Lua.
        vertexView = newView(),
        indexView = newView(),
        stats = { commands = 0, vertices = 0 },
    }, Renderer)
end

local function meshFor(self, index, vertices)
    local mesh = self.meshes[index]
    if not mesh or mesh:getVertexCount() < vertices then
        if mesh then
            mesh:release()
        end
        local capacity = 256
        while capacity < vertices do
            capacity = capacity * 2
        end
        mesh = katsa.graphics.newMesh(capacity, 'triangles', 'stream')
        self.meshes[index] = mesh
    end
    return mesh
end

-- Draws `drawData` (igGetDrawData()) into the current canvas, in logical pixels.
function Renderer:draw(drawData)
    self.textures:update(drawData)
    local stats = self.stats
    stats.commands, stats.vertices = 0, 0
    if drawData.TotalVtxCount == 0 then
        return
    end
    local g = katsa.graphics
    g.push('all')
    g.origin()
    g.setShader()
    g.setBlendMode('alpha')
    g.setDepthMode()
    g.setMeshCullMode('none')
    g.setWireframe(false)
    g.setColor(1, 1, 1, 1)
    local offsetX, offsetY = drawData.DisplayPos.x, drawData.DisplayPos.y
    for i = 0, drawData.CmdLists.Size - 1 do
        local list = drawData.CmdLists.Data[i]
        local vertexCount, indexCount = list.VtxBuffer.Size, list.IdxBuffer.Size
        if vertexCount > 0 and indexCount > 0 then
            local mesh = meshFor(self, i + 1, vertexCount)
            mesh:setVertices(point(self.vertexView, list.VtxBuffer.Data, vertexCount * VERTEX_BYTES))
            mesh:setVertexMap(point(self.indexView, list.IdxBuffer.Data, indexCount * INDEX_BYTES))
            for c = 0, list.CmdBuffer.Size - 1 do
                local command = list.CmdBuffer.Data[c]
                if command.UserCallback == nil and command.ElemCount > 0 then
                    local clip = command.ClipRect
                    local x1, y1 = clip.x - offsetX, clip.y - offsetY
                    local x2, y2 = clip.z - offsetX, clip.w - offsetY
                    if x2 > x1 and y2 > y1 then
                        local ref = command.TexRef
                        local id = ref._TexData ~= nil and ref._TexData.TexID or ref._TexID
                        local image = self.textures:get(tonumber(id))
                        if image then
                            g.setScissor(x1, y1, x2 - x1, y2 - y1)
                            mesh:setTexture(image)
                            mesh:setDrawRange(command.IdxOffset + 1, command.ElemCount)
                            g.draw(mesh)
                            stats.commands = stats.commands + 1
                        end
                    end
                end
            end
            stats.vertices = stats.vertices + vertexCount
        end
    end
    g.setScissor()
    g.pop()
end

function Renderer:release()
    for index, mesh in pairs(self.meshes) do
        mesh:release()
        self.meshes[index] = nil
    end
    self.textures:release()
end

return Renderer
