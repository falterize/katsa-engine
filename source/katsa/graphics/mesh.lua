-- Mesh objects: interleaved vertex buffers with optional index map, attached attributes and
-- instancing.
local ffi = require('ffi')
local Core = require('source.katsa.graphics.core')

local Mesh = {}
local Methods = {}
Methods.__index = Methods

Mesh.defaultFormat = {
    { 'VertexPosition', 'float', 2 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexColor', 'byte', 4 },
}

local builtinLocation = { VertexPosition = 0, VertexTexCoord = 1, VertexColor = 2 }
local drawModes = {
    fan = 'TRIANGLE_FAN',
    strip = 'TRIANGLE_STRIP',
    triangles = 'TRIANGLES',
    points = 'POINTS',
}
local usages = { stream = 'STREAM_DRAW', dynamic = 'DYNAMIC_DRAW', static = 'STATIC_DRAW' }

local function isFormat(value)
    return type(value) == 'table' and type(value[1]) == 'table' and type(value[1][1]) == 'string'
end

local function describe(format)
    local layout, offset = {}, 0
    for index, item in ipairs(format) do
        local name, kind, count = item[1], item[2], item[3]
        local size
        if kind == 'float' then
            size = 4 * count
        elseif kind == 'byte' then
            assert(count == 4, 'byte attributes must have 4 components')
            size = 4
        elseif kind == 'unorm16' then
            size = 2 * count
        else
            error('Unsupported vertex attribute type: ' .. tostring(kind))
        end
        layout[index] = { name = name, kind = kind, count = count, offset = offset, size = size }
        layout[name] = layout[index]
        offset = offset + size
    end
    return layout, offset
end

local function dataPointer(source)
    if type(source) == 'table' and source.getPointer and source.getSize then
        return source:getPointer(), source:getSize()
    end
end

function Mesh.new(...)
    local args = { ... }
    local format = Mesh.defaultFormat
    if isFormat(args[1]) then
        format = table.remove(args, 1)
    end
    local vertices, mode, usage = args[1], args[2] or 'fan', args[3] or 'dynamic'
    assert(drawModes[mode], 'Invalid mesh draw mode: ' .. tostring(mode))
    assert(usages[usage], 'Invalid mesh usage: ' .. tostring(usage))
    local layout, stride = describe(format)
    local count
    if type(vertices) == 'number' then
        count = vertices
    elseif type(vertices) == 'table' then
        count = #vertices
    else
        local _, size = dataPointer(vertices)
        assert(size, 'Invalid vertex data')
        count = math.floor(size / stride)
    end
    assert(count > 0, 'Mesh must have at least one vertex')
    local gl, E = Core.gl, Core.enum
    local id = ffi.new('GLuint[1]')
    gl.glGenBuffers(1, id)
    local self = setmetatable({
        _format = format, _layout = layout, _stride = stride, _count = count, _mode = mode,
        _usage = usage, _data = ffi.new('uint8_t[?]',
            count * stride), _buffer = id[0], _attached = {}, _disabled = {},
    }, Methods)
    self._res = { buffers = { id[0] } }
    self._floats = ffi.cast('float*', self._data)
    Core.track(self, self._res)
    gl.glBindBuffer(E.ARRAY_BUFFER, self._buffer)
    gl.glBufferData(E.ARRAY_BUFFER, count * stride, nil, E[usages[usage]])
    if type(vertices) == 'table' then
        self:setVertices(vertices)
    elseif type(vertices) ~= 'number' then
        self:setVertices(vertices)
    else
        self:_upload(0, count)
    end
    return self
end

function Methods:_upload(first, count)
    local gl, E = Core.gl, Core.enum
    gl.glBindBuffer(E.ARRAY_BUFFER, self._buffer)
    gl.glBufferSubData(E.ARRAY_BUFFER, first * self._stride, count * self._stride,
        self._data + first * self._stride)
end

local function writeComponent(self, attribute, vertexBase, c, value)
    local kind = attribute.kind
    if kind == 'float' then
        self._floats[(vertexBase + attribute.offset) / 4 + c - 1] = value
    elseif kind == 'byte' then
        local v = math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
        self._data[vertexBase + attribute.offset + c - 1] = v
    else
        local p = ffi.cast('uint16_t*', self._data + vertexBase + attribute.offset)
        p[c - 1] = math.floor(math.max(0, math.min(1, value)) * 65535 + 0.5)
    end
end

function Methods:setVertex(index, ...)
    local row = ...
    if type(row) ~= 'table' then
        row = { ... }
    end
    assert(index >= 1 and index <= self._count, 'Invalid vertex index: ' .. tostring(index))
    local base, cursor = (index - 1) * self._stride, 1
    for _, attribute in ipairs(self._layout) do
        for c = 1, attribute.count do
            local value = row[cursor]
            if value == nil then
                value = (attribute.kind == 'byte' or attribute.name == 'VertexColor') and 1 or 0
            end
            writeComponent(self, attribute, base, c, value)
            cursor = cursor + 1
        end
    end
    self:_upload(index - 1, 1)
end

function Methods:setVertices(vertices, startvertex, count)
    startvertex = startvertex or 1
    local pointer, size = dataPointer(vertices)
    if pointer then
        local vertexCount = math.floor(size / self._stride)
        count = math.min(count or vertexCount, vertexCount)
        assert(startvertex - 1 + count <= self._count, 'Too many vertices for the mesh')
        ffi.copy(self._data + (startvertex - 1) * self._stride, pointer, count * self._stride)
        self:_upload(startvertex - 1, count)
        return
    end
    count = count or #vertices
    assert(startvertex >= 1 and startvertex - 1 + count <= self._count,
        'Too many vertices for the mesh')
    local layout, stride = self._layout, self._stride
    local floats, data = self._floats, self._data
    for i = 1, count do
        local row = vertices[i]
        local base, cursor = (startvertex - 2 + i) * stride, 1
        for _, attribute in ipairs(layout) do
            local kind = attribute.kind
            local fill = (kind == 'byte' or attribute.name == 'VertexColor') and 1 or 0
            if kind == 'float' then
                local at = (base + attribute.offset) / 4
                for c = 0, attribute.count - 1 do
                    local value = row[cursor]
                    floats[at + c] = value == nil and fill or value
                    cursor = cursor + 1
                end
            else
                for c = 1, attribute.count do
                    local value = row[cursor]
                    writeComponent(self, attribute, base, c, value == nil and fill or value)
                    cursor = cursor + 1
                end
            end
        end
    end
    self:_upload(startvertex - 1, count)
end

function Methods:getVertex(index)
    assert(index >= 1 and index <= self._count, 'Invalid vertex index: ' .. tostring(index))
    local out, base = {}, (index - 1) * self._stride
    for _, attribute in ipairs(self._layout) do
        for c = 1, attribute.count do
            if attribute.kind == 'float' then
                out[#out + 1] = self._floats[(base + attribute.offset) / 4 + c - 1]
            elseif attribute.kind == 'byte' then
                out[#out + 1] = self._data[base + attribute.offset + c - 1] / 255
            else
                out[#out + 1] = ffi.cast('uint16_t*',
                    self._data + base + attribute.offset)[c - 1] / 65535
            end
        end
    end
    return unpack(out)
end

function Methods:getVertexCount()
    return
    self._count
end

function Methods:getVertexFormat()
    return
    self._format
end

function Methods:getDrawMode()
    return
    self._mode
end

function Methods:setDrawMode(mode)
    assert(drawModes[mode], 'Invalid mesh draw mode: ' .. tostring(mode))
    self._mode = mode
end

function Methods:setTexture(texture)
    self._texture = texture
end

function Methods:getTexture()
    return
    self._texture
end

function Methods:flush() end

function Methods:setDrawRange(start, count)
    if start == nil then
        self._rangeStart, self._rangeCount = nil, nil
        return
    end
    assert(start >= 1 and count and count >= 1, 'Invalid draw range')
    self._rangeStart, self._rangeCount = start, count
end

function Methods:getDrawRange()
    if self._rangeStart then
        return self._rangeStart, self._rangeCount
    end
end

function Methods:setVertexMap(...)
    local gl, E = Core.gl, Core.enum
    local first = ...
    if first == nil then
        self._indexCount, self._map = nil, nil
        return
    end
    local indices = first
    if type(first) == 'number' then
        indices = { ... }
    end
    local pointer, size = dataPointer(indices)
    local count, typeEnum, buffer
    if pointer then
        count = math.floor(size / 2)
        typeEnum = E.UNSIGNED_SHORT
        buffer = pointer
    else
        count = #indices
        local wide = self._count > 65535
        typeEnum = wide and E.UNSIGNED_INT or E.UNSIGNED_SHORT
        buffer = ffi.new(wide and 'uint32_t[?]' or 'uint16_t[?]', count)
        for i = 1, count do
            buffer[i - 1] = indices[i] - 1
        end
        self._map = indices
    end
    if not self._indexBuffer then
        local id = ffi.new('GLuint[1]')
        gl.glGenBuffers(1, id)
        self._indexBuffer = id[0]
        self._res.buffers[#self._res.buffers + 1] = id[0]
    end
    self._indexCount, self._indexType = count, typeEnum
    Core.bindElementBuffer(self._indexBuffer)
    gl.glBufferData(E.ELEMENT_ARRAY_BUFFER, count * (typeEnum == E.UNSIGNED_INT and 4 or 2), buffer,
        E.DYNAMIC_DRAW)
end

function Methods:getVertexMap()
    return self._map
end

function Methods:setAttributeEnabled(name, enabled)
    assert(self._layout[name] or self._attached[name],
        'Mesh does not have an attribute named ' .. tostring(name))
    self._disabled[name] = not enabled or nil
end

function Methods:isAttributeEnabled(name)
    assert(self._layout[name] or self._attached[name],
        'Mesh does not have an attribute named ' .. tostring(name))
    return not self._disabled[name]
end

function Methods:attachAttribute(name, other, step, attachName)
    step = step or 'pervertex'
    attachName = attachName or name
    assert(step == 'pervertex' or step == 'perinstance',
        'Invalid vertex attribute step: ' .. tostring(step))
    assert(other ~= self, 'Cannot attach an attribute of a mesh to itself')
    local attribute = other._layout[attachName]
    assert(attribute,
        'The specified mesh does not have a vertex attribute named ' .. tostring(attachName))
    self._attached[name] = { mesh = other, attribute = attribute, step = step }
end

function Methods:detachAttribute(name)
    local had = self._attached[name] ~= nil
    self._attached[name] = nil
    return had
end

local glTypes
-- Points the shader's attribute locations at this mesh (or its attached meshes).
function Methods:_bindAttributes(shader)
    local gl, E = Core.gl, Core.enum
    glTypes = glTypes or { float = E.FLOAT, byte = E.UNSIGNED_BYTE, unorm16 = E.UNSIGNED_SHORT }
    local wanted = {}
    local function bind(location, owner, attribute, step)
        gl.glBindBuffer(E.ARRAY_BUFFER, owner._buffer)
        local normalized = attribute.kind ~= 'float' and 1 or 0
        local offset = ffi.cast('void*', attribute.offset)
        gl.glVertexAttribPointer(location, attribute.count, glTypes[attribute.kind], normalized,
            owner._stride, offset)
        gl.glEnableVertexAttribArray(location)
        gl.glVertexAttribDivisor(location, step == 'perinstance' and 1 or 0)
        wanted[location] = true
    end
    local function attach(name, location)
        if self._disabled[name] then
            return false
        end
        local attached = self._attached[name]
        if attached then
            bind(location, attached.mesh, attached.attribute, attached.step)
            return true
        end
        local own = self._layout[name]
        if own then
            bind(location, self, own, 'pervertex')
            return true
        end
        return false
    end
    for name, location in pairs(builtinLocation) do
        if not attach(name, location) then
            if name == 'VertexColor' then
                gl.glVertexAttrib4f(2, 1, 1, 1, 1)
            elseif name == 'VertexTexCoord' then
                gl.glVertexAttrib4f(1, 0, 0, 0, 1)
            else
                gl.glVertexAttrib4f(0, 0, 0, 0, 1)
            end
        end
    end
    for name, location in pairs(shader._attributeLocations) do
        if not attach(name, location) then
            gl.glVertexAttrib4f(location, 0, 0, 0, 1)
        end
    end
    Core.setEnabledAttributes(wanted)
end

function Methods:_draw(instances)
    local gl, E = Core.gl, Core.enum
    local mode = E[drawModes[self._mode]]
    local start, count = 0, self._count
    if self._indexCount then
        local size = self._indexType == E.UNSIGNED_INT and 4 or 2
        start, count = 0, self._indexCount
        if self._rangeStart then
            start = self._rangeStart - 1
            count = math.min(self._rangeCount, self._indexCount - start)
        end
        Core.bindElementBuffer(self._indexBuffer)
        local offset = ffi.cast('void*', start * size)
        if instances and instances > 1 then
            gl.glDrawElementsInstanced(mode, count, self._indexType, offset, instances)
        else
            gl.glDrawElements(mode, count, self._indexType, offset)
        end
    else
        if self._rangeStart then
            start = self._rangeStart - 1
            count = math.min(self._rangeCount, self._count - start)
        end
        if instances and instances > 1 then
            gl.glDrawArraysInstanced(mode, start, count, instances)
        else
            gl.glDrawArrays(mode, start, count)
        end
    end
    return count
end

function Methods:release()
    return
    Core.release(self)
end

function Methods:type()
    return 'Mesh'
end

function Methods:typeOf(name)
    return name == 'Mesh' or name == 'Drawable' or name == 'Object'
end

return Mesh
