-- Compiles and links translated shaders on whatever GL context is current. Used by tests and by
-- `katsa --validate-shaders`; the runtime graphics layer uses the same entry points.
local ffi = require('ffi')

ffi.cdef([[
typedef unsigned int GLenum; typedef unsigned int GLuint; typedef int GLint; typedef int GLsizei;
typedef char GLchar; typedef unsigned char GLubyte;
const GLubyte* glGetString(GLenum);
]])

local Check = {}
Check.__index = Check

local VERTEX, FRAGMENT = 0x8B31, 0x8B30
local COMPILE_STATUS, LINK_STATUS, INFO_LOG_LENGTH = 0x8B81, 0x8B82, 0x8B84
local functions = {
    glCreateShader = 'GLuint (*)(GLenum)',
    glShaderSource = 'void (*)(GLuint, GLsizei, const GLchar* const*, const GLint*)',
    glCompileShader = 'void (*)(GLuint)',
    glGetShaderiv = 'void (*)(GLuint, GLenum, GLint*)',
    glGetShaderInfoLog = 'void (*)(GLuint, GLsizei, GLsizei*, GLchar*)',
    glDeleteShader = 'void (*)(GLuint)',
    glCreateProgram = 'GLuint (*)(void)',
    glAttachShader = 'void (*)(GLuint, GLuint)',
    glLinkProgram = 'void (*)(GLuint)',
    glGetProgramiv = 'void (*)(GLuint, GLenum, GLint*)',
    glGetProgramInfoLog = 'void (*)(GLuint, GLsizei, GLsizei*, GLchar*)',
    glDeleteProgram = 'void (*)(GLuint)',
    glGetAttribLocation = 'GLint (*)(GLuint, const GLchar*)',
    glGetString = 'const GLubyte* (*)(GLenum)',
}

function Check.new(platform)
    local self = setmetatable({ gl = {} }, Check)
    for name, signature in pairs(functions) do
        local address = platform:getProcAddress(name)
        if not address then
            return nil, 'Missing GL entry point: ' .. name
        end
        self.gl[name] = ffi.cast(signature, address)
    end
    return self
end

function Check:info()
    local gl = self.gl
    return ffi.string(gl.glGetString(0x1F02)), ffi.string(gl.glGetString(0x1F01))
end

local function log(gl, object, getter, logger)
    local length = ffi.new('GLint[1]')
    getter(object, INFO_LOG_LENGTH, length)
    if length[0] <= 1 then
        return ''
    end
    local buffer = ffi.new('GLchar[?]', length[0])
    logger(object, length[0], nil, buffer)
    return ffi.string(buffer)
end

function Check:compile(kind, text)
    local gl = self.gl
    local shader = gl.glCreateShader(kind)
    local pointer = ffi.new('const GLchar*[1]', ffi.cast('const GLchar*', text))
    local length = ffi.new('GLint[1]', #text)
    gl.glShaderSource(shader, 1, pointer, length)
    gl.glCompileShader(shader)
    local status = ffi.new('GLint[1]')
    gl.glGetShaderiv(shader, COMPILE_STATUS, status)
    if status[0] == 0 then
        local message = log(gl, shader, gl.glGetShaderiv, gl.glGetShaderInfoLog)
        gl.glDeleteShader(shader)
        return nil, message
    end
    return shader
end

-- translated: result of shaderTranslator.translate. Returns true, or false and a message.
function Check:link(translated)
    local gl = self.gl
    local vertex, message = self:compile(VERTEX, translated.vertex)
    if not vertex then
        return false, 'vertex: ' .. message
    end
    local pixel
    pixel, message = self:compile(FRAGMENT, translated.pixel)
    if not pixel then
        gl.glDeleteShader(vertex)
        return false, 'pixel: ' .. message
    end
    local program = gl.glCreateProgram()
    gl.glAttachShader(program, vertex)
    gl.glAttachShader(program, pixel)
    gl.glLinkProgram(program)
    local status = ffi.new('GLint[1]')
    gl.glGetProgramiv(program, LINK_STATUS, status)
    local ok = status[0] ~= 0
    local linkLog = ok and '' or log(gl, program, gl.glGetProgramiv, gl.glGetProgramInfoLog)
    if ok then
        -- Locations assigned by the translator must be what the driver reports.
        for name, attribute in pairs(translated.attributes or {}) do
            local actual = gl.glGetAttribLocation(program, name)
            if actual >= 0 and actual ~= attribute.location then
                ok, linkLog =
                    false,
                    ('attribute %s expected location %d, got %d'):format(
                        name,
                        attribute.location,
                        actual
                    )
            end
        end
    end
    gl.glDeleteProgram(program)
    gl.glDeleteShader(vertex)
    gl.glDeleteShader(pixel)
    return ok, linkLog
end

return Check
