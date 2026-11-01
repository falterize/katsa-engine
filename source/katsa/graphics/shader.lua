-- Shader objects: translate (shaderTranslator), compile, link, uniform introspection and sending.
local ffi = require('ffi')
local Core = require('source.katsa.graphics.core')
local Translator = require('source.katsa.graphics.shaderTranslator')

local Shader = {}
local Methods = {}
Methods.__index = Methods

local scratch = ffi.new('float[?]', 16384)
local iscratch = ffi.new('GLint[?]', 4096)

local function typeInfo()
    local E = Core.enum
    return {
        [E.FLOAT] = { 'float', 1 }, [E.FLOAT_VEC2] = { 'float', 2 },
        [E.FLOAT_VEC3] = { 'float', 3 },
        [E.FLOAT_VEC4] = { 'float', 4 }, [E.INT] = { 'int', 1 }, [E.INT_VEC2] = { 'int', 2 },
        [E.INT_VEC3] = { 'int', 3 }, [E.INT_VEC4] = { 'int', 4 }, [E.BOOL] = { 'bool', 1 },
        [0x8B57] = { 'bool', 2 }, [0x8B58] = { 'bool', 3 }, [0x8B59] = { 'bool', 4 },
        [E.FLOAT_MAT2] = { 'matrix', 4, 2 }, [E.FLOAT_MAT3] = { 'matrix', 9, 3 },
        [E.FLOAT_MAT4] = { 'matrix', 16, 4 },
        [E.SAMPLER_2D] = { 'sampler', 1 },
    }
end

local function infoLog(object, isProgram)
    local gl, E = Core.gl, Core.enum
    local length = ffi.new('GLint[1]')
    if isProgram then
        gl.glGetProgramiv(object, E.INFO_LOG_LENGTH, length)
    else
        gl.glGetShaderiv(object, E.INFO_LOG_LENGTH, length)
    end
    if length[0] <= 1 then
        return ''
    end
    local buffer = ffi.new('GLchar[?]', length[0])
    if isProgram then
        gl.glGetProgramInfoLog(object, length[0], nil, buffer)
    else
        gl.glGetShaderInfoLog(object, length[0], nil, buffer)
    end
    return ffi.string(buffer)
end

local function compileStage(kind, text, label)
    local gl, E = Core.gl, Core.enum
    local shader = gl.glCreateShader(kind)
    local pointer = ffi.new('const GLchar*[1]', ffi.cast('const GLchar*', text))
    local length = ffi.new('GLint[1]', #text)
    gl.glShaderSource(shader, 1, pointer, length)
    gl.glCompileShader(shader)
    local status = ffi.new('GLint[1]')
    gl.glGetShaderiv(shader, E.COMPILE_STATUS, status)
    if status[0] == 0 then
        local log = infoLog(shader, false)
        gl.glDeleteShader(shader)
        return nil, ('Cannot compile %s shader code:\n%s'):format(label, log)
    end
    return shader
end

-- Reads a shader from `code`, which is either source text or a file name.
local function resolveSource(code)
    if type(code) ~= 'string' then
        error('Shader source must be a string', 3)
    end
    if not code:find('\n', 1, true) and #code < 1024 then
        local FS = require('source.katsa.core.filesystem')
        if FS.getInfo(code, 'file') then
            return FS.read(code)
        end
        if code:match('%.glsl$') then
            error('Could not open file ' .. code .. '. Does not exist.', 3)
        end
    end
    return code
end

local function build(source, renderTargets)
    local translated, message = Translator.translate(source, {
        target = Core.es and 'es' or 'desktop',
        renderTargets = renderTargets,
    })
    if not translated then
        return nil, message
    end
    local gl, E = Core.gl, Core.enum
    local vertex, err = compileStage(E.VERTEX_SHADER, translated.vertex, 'vertex')
    if not vertex then
        return nil, err
    end
    local pixel
    pixel, err = compileStage(E.FRAGMENT_SHADER, translated.pixel, 'pixel')
    if not pixel then
        gl.glDeleteShader(vertex)
        return nil, err
    end
    local program = gl.glCreateProgram()
    gl.glAttachShader(program, vertex)
    gl.glAttachShader(program, pixel)
    gl.glLinkProgram(program)
    gl.glDeleteShader(vertex)
    gl.glDeleteShader(pixel)
    local status = ffi.new('GLint[1]')
    gl.glGetProgramiv(program, E.LINK_STATUS, status)
    if status[0] == 0 then
        local log = infoLog(program, true)
        gl.glDeleteProgram(program)
        return nil, 'Cannot link shader program:\n' .. log
    end
    return program, translated
end

function Shader.validate(code)
    local ok, source = pcall(resolveSource, code)
    if not ok then
        return false, source
    end
    local program, translated = build(source)
    if not program then
        return false, translated
    end
    Core.gl.glDeleteProgram(program)
    return true, ''
end

function Shader.new(code, extra)
    assert(extra == nil, 'Separate vertex and pixel sources are not supported; use one source')
    local source = resolveSource(code)
    local program, translated = build(source)
    if not program then
        error(translated, 2)
    end
    local gl, E = Core.gl, Core.enum
    local self = setmetatable({
        _program = program, _uniforms = {}, _attributes = translated.attributes or {},
        _attributeOrder = translated.attributeOrder or {},
        _renderTargets = translated.renderTargets or 1,
        _source = source, _samplers = {},
    }, Methods)
    local types = typeInfo()
    local count = ffi.new('GLint[1]')
    gl.glGetProgramiv(program, E.ACTIVE_UNIFORMS, count)
    local maxLength = ffi.new('GLint[1]')
    gl.glGetProgramiv(program, E.ACTIVE_UNIFORM_MAX_LENGTH, maxLength)
    local nameBuffer = ffi.new('GLchar[?]', math.max(maxLength[0], 2))
    local size, kind = ffi.new('GLint[1]'), ffi.new('GLenum[1]')
    Core.useProgram(program)
    local unit = 1
    for i = 0, count[0] - 1 do
        gl.glGetActiveUniform(program, i, maxLength[0], nil, size, kind, nameBuffer)
        local name = ffi.string(nameBuffer)
        local location = gl.glGetUniformLocation(program, name)
        if location >= 0 then
            local base = name:gsub('%[0%]$', '')
            local info = types[kind[0]]
            local entry = {
                name = base,
                location = location,
                count = size[0],
                info = info,
                glType = kind[0],
            }
            self._uniforms[base] = entry
            if info and info[1] == 'sampler' and base ~= 'MainTex' then
                entry.unit = unit
                local units = ffi.new('GLint[?]', size[0])
                for u = 0, size[0] - 1 do
                    units[u] = unit + u
                end
                gl.glUniform1iv(location, size[0], units)
                unit = unit + size[0]
                self._samplers[#self._samplers + 1] = entry
                entry.textures = {}
            end
        end
    end
    local main = self._uniforms.MainTex
    if main then
        gl.glUniform1i(main.location, 0)
    end
    self._builtin = {}
    local builtins = {
        'TransformMatrix', 'ProjectionMatrix', 'TransformProjectionMatrix', 'NormalMatrix',
        'ConstantColor', 'katsa_PointSize', 'katsa_ScreenSize',
    }
    for _, name in ipairs(builtins) do
        local entry = self._uniforms[name]
        self._builtin[name] = entry and entry.location or -1
        self._uniforms[name] = nil
    end
    self._uniforms.MainTex = nil
    self._attributeLocations = {}
    for name, a in pairs(self._attributes) do
        self._attributeLocations[name] = a.location
    end
    Core.track(self, { program = program })
    return self
end

function Methods:hasUniform(name)
    return self._uniforms[name] ~= nil
end

function Methods:getWarnings()
    return ''
end

function Methods:getExternVariable(name)
    local u = self._uniforms[name]
    if not u then
        return nil
    end
    return u.info and u.info[1] or 'unknown', u.info and u.info[2] or 1, u.count
end

local function toNumber(value, name)
    local kind = type(value)
    if kind == 'number' then
        return value
    elseif kind == 'boolean' then
        return value and 1 or 0
    end
    error(('Invalid value for uniform %s: expected number, got %s'):format(name, kind), 3)
end

-- Writes `values` (array of numbers or tables) into the scratch buffer; returns element count.
local function packComponents(entry, values, componentCount, buffer, transposeRows)
    local out, name = 0, entry.name
    local limit = entry.count
    for index = 1, math.min(#values, limit) do
        local v = values[index]
        if type(v) == 'table' then
            if #v < componentCount and entry.info[1] ~= 'matrix' then
                local message = 'Invalid number of components for uniform %s: expected %d, got %d'
                error(message:format(name, componentCount, #v), 3)
            end
            if entry.info[1] == 'matrix' and type(v[1]) == 'table' then
                -- nested rows -> flat row-major
                local dim = entry.info[3]
                for r = 1, dim do
                    for c = 1, dim do
                        buffer[out] = v[r][c]
                        out = out + 1
                    end
                end
            else
                for c = 1, componentCount do
                    buffer[out] = toNumber(v[c], name)
                    out = out + 1
                end
            end
        elseif componentCount == 1 then
            buffer[out] = toNumber(v, name)
            out = out + 1
        else
            error(('Invalid value for uniform %s: expected a table with %d components'):format(name,
                componentCount), 3)
        end
    end
    return #values > limit and limit or #values
end

-- Vector and matrix uniforms also accept their components as plain numbers; group them per element.
local function groupFlatNumbers(values, size)
    if size == 1 or type(values[1]) ~= 'number' then
        return values
    end
    local grouped = {}
    for first = 1, #values, size do
        grouped[#grouped + 1] = { unpack(values, first, first + size - 1) }
    end
    return grouped
end

function Methods:send(name, ...)
    local entry = self._uniforms[name]
    if not entry then
        local message = "Shader uniform '%s' does not exist.\n"
            .. 'A common error is to define but not use the variable.'
        error(message:format(name), 2)
    end
    -- Queued draws must see the old uniform values and textures (flush before changing state).
    require('source.katsa.graphics.state').flush()
    local gl = Core.gl
    local info = entry.info
    if not info then
        error('Unsupported uniform type for ' .. name, 2)
    end
    local args = { ... }
    local layout = 'row'
    if info[1] == 'matrix' and (args[1] == 'row' or args[1] == 'column') then
        layout = table.remove(args, 1)
    end
    Core.useProgram(self._program)
    if info[1] == 'sampler' then
        for i = 1, math.min(#args, entry.count) do
            local texture = args[i]
            local isTexture = type(texture) == 'table'
                and (texture._info or (texture._res and texture._res.texture))
            if isTexture then
                entry.textures[i] = texture
            else
                error('Invalid texture for uniform ' .. name, 2)
            end
        end
        return
    end
    local values = args
    if #args == 1 and type(args[1]) == 'table' then
        if entry.count > 1 then
            values = args[1]
        elseif info[2] == 1 and info[1] ~= 'matrix' then
            values = args[1]
        else
            values = { args[1] }
        end
    end
    -- Extra values are dropped: drivers report only the used part of an array as its size.
    local kind, comps = info[1], info[2]
    values = groupFlatNumbers(values, comps)
    if #values > entry.count then
        values = { unpack(values, 1, entry.count) }
    end
    if kind == 'float' then
        local n = packComponents(entry, values, comps, scratch)
        local fn = ({ gl.glUniform1fv, gl.glUniform2fv, gl.glUniform3fv, gl.glUniform4fv })[comps]
        fn(entry.location, n, scratch)
    elseif kind == 'int' or kind == 'bool' then
        local out = 0
        for index = 1, #values do
            local v = values[index]
            if type(v) == 'table' then
                for c = 1, comps do
                    iscratch[out] = toNumber(v[c], name)
                    out = out + 1
                end
            else
                iscratch[out] = toNumber(v, name)
                out = out + 1
            end
        end
        local fn = ({ gl.glUniform1iv, gl.glUniform2iv, gl.glUniform3iv, gl.glUniform4iv })[comps]
        fn(entry.location, #values, iscratch)
    else
        local n = packComponents(entry, values, comps, scratch)
        local matrixUniforms = {
            [4] = gl.glUniformMatrix2fv,
            [9] = gl.glUniformMatrix3fv,
            [16] = gl.glUniformMatrix4fv,
        }
        local fn = matrixUniforms[comps]
        fn(entry.location, n, layout == 'row' and 1 or 0, scratch)
    end
end

function Methods:sendColor(name, ...)
    local args = { ... }
    for i, color in ipairs(args) do
        args[i] = { color[1], color[2], color[3], color[4] or 1 }
    end
    return self:send(name, unpack(args))
end

-- Binds user sampler textures to their units.
function Methods:_bindSamplers()
    for _, entry in ipairs(self._samplers) do
        for i = 0, entry.count - 1 do
            local texture = entry.textures[i + 1]
            Core.bindTexture(entry.unit + i,
                texture and texture:_sampleId() or Core.defaultTextureId)
        end
    end
end

function Methods:release()
    return Core.release(self)
end

function Methods:type()
    return 'Shader'
end

function Methods:typeOf(name)
    return name == 'Shader' or name == 'Object'
end

return Shader
