-- OpenGL entry points used by katsa.graphics, loaded through the platform's getProcAddress.
-- Everything is GL 3.3 core / GLES 3.0 compatible; desktop-only calls are not used.
local ffi = require('ffi')

ffi.cdef([[
typedef unsigned int GLenum; typedef unsigned int GLuint; typedef int GLint; typedef int GLsizei;
typedef char GLchar; typedef unsigned char GLubyte; typedef unsigned char GLboolean;
typedef float GLfloat; typedef unsigned int GLbitfield; typedef ptrdiff_t GLsizeiptr;
typedef ptrdiff_t GLintptr;
]])

local GL = { C = {} }

GL.signatures = {
    glGetString = 'const GLubyte* (*)(GLenum)',
    glGetIntegerv = 'void (*)(GLenum, GLint*)',
    glGetFloatv = 'void (*)(GLenum, GLfloat*)',
    glGetError = 'GLenum (*)(void)',
    glGetStringi = 'const GLubyte* (*)(GLenum, GLuint)',
    glEnable = 'void (*)(GLenum)',
    glDisable = 'void (*)(GLenum)',
    glViewport = 'void (*)(GLint, GLint, GLsizei, GLsizei)',
    glScissor = 'void (*)(GLint, GLint, GLsizei, GLsizei)',
    glClearColor = 'void (*)(GLfloat, GLfloat, GLfloat, GLfloat)',
    glClearDepthf = 'void (*)(GLfloat)',
    glClearStencil = 'void (*)(GLint)',
    glClear = 'void (*)(GLbitfield)',
    glColorMask = 'void (*)(GLboolean, GLboolean, GLboolean, GLboolean)',
    glDepthMask = 'void (*)(GLboolean)',
    glDepthFunc = 'void (*)(GLenum)',
    glStencilFunc = 'void (*)(GLenum, GLint, GLuint)',
    glStencilOp = 'void (*)(GLenum, GLenum, GLenum)',
    glStencilMask = 'void (*)(GLuint)',
    glBlendFuncSeparate = 'void (*)(GLenum, GLenum, GLenum, GLenum)',
    glBlendEquationSeparate = 'void (*)(GLenum, GLenum)',
    glCullFace = 'void (*)(GLenum)',
    glFrontFace = 'void (*)(GLenum)',
    glLineWidth = 'void (*)(GLfloat)',
    glPixelStorei = 'void (*)(GLenum, GLint)',
    glReadPixels = 'void (*)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void*)',
    glFlush = 'void (*)(void)',
    glFinish = 'void (*)(void)',
    -- textures
    glGenTextures = 'void (*)(GLsizei, GLuint*)',
    glDeleteTextures = 'void (*)(GLsizei, const GLuint*)',
    glBindTexture = 'void (*)(GLenum, GLuint)',
    glActiveTexture = 'void (*)(GLenum)',
    glTexImage2D = 'void (*)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*)',
    glTexSubImage2D = 'void (*)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const void*)',
    glTexParameteri = 'void (*)(GLenum, GLenum, GLint)',
    glTexParameterf = 'void (*)(GLenum, GLenum, GLfloat)',
    glGenerateMipmap = 'void (*)(GLenum)',
    glTexStorage2D = 'void (*)(GLenum, GLsizei, GLenum, GLsizei, GLsizei)',
    -- framebuffers
    glGenFramebuffers = 'void (*)(GLsizei, GLuint*)',
    glDeleteFramebuffers = 'void (*)(GLsizei, const GLuint*)',
    glBindFramebuffer = 'void (*)(GLenum, GLuint)',
    glFramebufferTexture2D = 'void (*)(GLenum, GLenum, GLenum, GLuint, GLint)',
    glFramebufferRenderbuffer = 'void (*)(GLenum, GLenum, GLenum, GLuint)',
    glCheckFramebufferStatus = 'GLenum (*)(GLenum)',
    glDrawBuffers = 'void (*)(GLsizei, const GLenum*)',
    glBlitFramebuffer = 'void (*)(GLint, GLint, GLint, GLint, GLint, GLint, GLint, GLint, GLbitfield, GLenum)',
    glGenRenderbuffers = 'void (*)(GLsizei, GLuint*)',
    glDeleteRenderbuffers = 'void (*)(GLsizei, const GLuint*)',
    glBindRenderbuffer = 'void (*)(GLenum, GLuint)',
    glRenderbufferStorage = 'void (*)(GLenum, GLenum, GLsizei, GLsizei)',
    glRenderbufferStorageMultisample = 'void (*)(GLenum, GLsizei, GLenum, GLsizei, GLsizei)',
    glInvalidateFramebuffer = 'void (*)(GLenum, GLsizei, const GLenum*)',
    -- buffers and vertex arrays
    glGenBuffers = 'void (*)(GLsizei, GLuint*)',
    glDeleteBuffers = 'void (*)(GLsizei, const GLuint*)',
    glBindBuffer = 'void (*)(GLenum, GLuint)',
    glBufferData = 'void (*)(GLenum, GLsizeiptr, const void*, GLenum)',
    glBufferSubData = 'void (*)(GLenum, GLintptr, GLsizeiptr, const void*)',
    glGenVertexArrays = 'void (*)(GLsizei, GLuint*)',
    glDeleteVertexArrays = 'void (*)(GLsizei, const GLuint*)',
    glBindVertexArray = 'void (*)(GLuint)',
    glEnableVertexAttribArray = 'void (*)(GLuint)',
    glDisableVertexAttribArray = 'void (*)(GLuint)',
    glVertexAttribPointer = 'void (*)(GLuint, GLint, GLenum, GLboolean, GLsizei, const void*)',
    glVertexAttrib4f = 'void (*)(GLuint, GLfloat, GLfloat, GLfloat, GLfloat)',
    glVertexAttribDivisor = 'void (*)(GLuint, GLuint)',
    glDrawArrays = 'void (*)(GLenum, GLint, GLsizei)',
    glDrawElements = 'void (*)(GLenum, GLsizei, GLenum, const void*)',
    glDrawArraysInstanced = 'void (*)(GLenum, GLint, GLsizei, GLsizei)',
    glDrawElementsInstanced = 'void (*)(GLenum, GLsizei, GLenum, const void*, GLsizei)',
    -- shaders
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
    glUseProgram = 'void (*)(GLuint)',
    glGetUniformLocation = 'GLint (*)(GLuint, const GLchar*)',
    glGetActiveUniform = 'void (*)(GLuint, GLuint, GLsizei, GLsizei*, GLint*, GLenum*, GLchar*)',
    glUniform1i = 'void (*)(GLint, GLint)',
    glUniform1fv = 'void (*)(GLint, GLsizei, const GLfloat*)',
    glUniform2fv = 'void (*)(GLint, GLsizei, const GLfloat*)',
    glUniform3fv = 'void (*)(GLint, GLsizei, const GLfloat*)',
    glUniform4fv = 'void (*)(GLint, GLsizei, const GLfloat*)',
    glUniform1iv = 'void (*)(GLint, GLsizei, const GLint*)',
    glUniform2iv = 'void (*)(GLint, GLsizei, const GLint*)',
    glUniform3iv = 'void (*)(GLint, GLsizei, const GLint*)',
    glUniform4iv = 'void (*)(GLint, GLsizei, const GLint*)',
    glUniformMatrix2fv = 'void (*)(GLint, GLsizei, GLboolean, const GLfloat*)',
    glUniformMatrix3fv = 'void (*)(GLint, GLsizei, GLboolean, const GLfloat*)',
    glUniformMatrix4fv = 'void (*)(GLint, GLsizei, GLboolean, const GLfloat*)',
}

GL.enum = {
    FALSE = 0, TRUE = 1,
    COLOR_BUFFER_BIT = 0x4000, DEPTH_BUFFER_BIT = 0x100, STENCIL_BUFFER_BIT = 0x400,
    POINTS = 0, LINES = 1, LINE_STRIP = 3, TRIANGLES = 4, TRIANGLE_STRIP = 5, TRIANGLE_FAN = 6,
    BYTE = 0x1400, UNSIGNED_BYTE = 0x1401, UNSIGNED_SHORT = 0x1403, UNSIGNED_INT = 0x1405, FLOAT = 0x1406,
    HALF_FLOAT = 0x140B,
    ZERO = 0, ONE = 1, SRC_COLOR = 0x300, ONE_MINUS_SRC_COLOR = 0x301, SRC_ALPHA = 0x302,
    ONE_MINUS_SRC_ALPHA = 0x303, DST_ALPHA = 0x304, ONE_MINUS_DST_ALPHA = 0x305,
    DST_COLOR = 0x306, ONE_MINUS_DST_COLOR = 0x307,
    FUNC_ADD = 0x8006, FUNC_SUBTRACT = 0x800A, FUNC_REVERSE_SUBTRACT = 0x800B, MIN = 0x8007, MAX = 0x8008,
    FRONT = 0x404, BACK = 0x405, CW = 0x900, CCW = 0x901,
    CULL_FACE = 0xB44, DEPTH_TEST = 0xB71, STENCIL_TEST = 0xB90, BLEND = 0xBE2, SCISSOR_TEST = 0xC11,
    NEVER = 0x200, LESS = 0x201, EQUAL = 0x202, LEQUAL = 0x203, GREATER = 0x204, NOTEQUAL = 0x205,
    GEQUAL = 0x206, ALWAYS = 0x207,
    KEEP = 0x1E00, REPLACE = 0x1E01, INCR = 0x1E02, DECR = 0x1E03, INVERT = 0x150A,
    INCR_WRAP = 0x8507, DECR_WRAP = 0x8508,
    TEXTURE_2D = 0xDE1, TEXTURE0 = 0x84C0,
    TEXTURE_MAG_FILTER = 0x2800, TEXTURE_MIN_FILTER = 0x2801, TEXTURE_WRAP_S = 0x2802, TEXTURE_WRAP_T = 0x2803,
    NEAREST = 0x2600, LINEAR = 0x2601, NEAREST_MIPMAP_NEAREST = 0x2700, LINEAR_MIPMAP_NEAREST = 0x2701,
    NEAREST_MIPMAP_LINEAR = 0x2702, LINEAR_MIPMAP_LINEAR = 0x2703,
    REPEAT = 0x2901, CLAMP_TO_EDGE = 0x812F, MIRRORED_REPEAT = 0x8370,
    RED = 0x1903, RG = 0x8227, RGB = 0x1907, RGBA = 0x1908, DEPTH_COMPONENT = 0x1902, DEPTH_STENCIL = 0x84F9,
    R8 = 0x8229, RG8 = 0x822B, RGB8 = 0x8051, RGBA8 = 0x8058, RGBA16F = 0x881A, RGBA32F = 0x8814,
    R16F = 0x822D, R32F = 0x822E, RG16F = 0x822F, RGB10_A2 = 0x8059, SRGB8_ALPHA8 = 0x8C43,
    DEPTH_COMPONENT16 = 0x81A5, DEPTH_COMPONENT24 = 0x81A6, DEPTH_COMPONENT32F = 0x8CAC,
    DEPTH24_STENCIL8 = 0x88F0, DEPTH32F_STENCIL8 = 0x8CAD, STENCIL_INDEX8 = 0x8D48,
    UNSIGNED_INT_24_8 = 0x84FA,
    FRAMEBUFFER = 0x8D40, READ_FRAMEBUFFER = 0x8CA8, DRAW_FRAMEBUFFER = 0x8CA9, RENDERBUFFER = 0x8D41,
    COLOR_ATTACHMENT0 = 0x8CE0, DEPTH_ATTACHMENT = 0x8D00, STENCIL_ATTACHMENT = 0x8D20,
    DEPTH_STENCIL_ATTACHMENT = 0x821A, FRAMEBUFFER_COMPLETE = 0x8CD5,
    ARRAY_BUFFER = 0x8892, ELEMENT_ARRAY_BUFFER = 0x8893,
    STREAM_DRAW = 0x88E0, STATIC_DRAW = 0x88E4, DYNAMIC_DRAW = 0x88E8,
    VERTEX_SHADER = 0x8B31, FRAGMENT_SHADER = 0x8B30,
    COMPILE_STATUS = 0x8B81, LINK_STATUS = 0x8B82, INFO_LOG_LENGTH = 0x8B84,
    ACTIVE_UNIFORMS = 0x8B86, ACTIVE_UNIFORM_MAX_LENGTH = 0x8B87,
    FLOAT_VEC2 = 0x8B50, FLOAT_VEC3 = 0x8B51, FLOAT_VEC4 = 0x8B52, INT = 0x1404,
    INT_VEC2 = 0x8B53, INT_VEC3 = 0x8B54, INT_VEC4 = 0x8B55, BOOL = 0x8B56,
    FLOAT_MAT2 = 0x8B5A, FLOAT_MAT3 = 0x8B5B, FLOAT_MAT4 = 0x8B5C,
    SAMPLER_2D = 0x8B5E, SAMPLER_3D = 0x8B5F, SAMPLER_CUBE = 0x8B60, SAMPLER_2D_ARRAY = 0x8DC1,
    VENDOR = 0x1F00, RENDERER = 0x1F01, VERSION = 0x1F02,
    NUM_EXTENSIONS = 0x821D, MAX_TEXTURE_SIZE = 0xD33, MAX_RENDERBUFFER_SIZE = 0x84E8, MAX_SAMPLES = 0x8D57,
    MAX_COLOR_ATTACHMENTS = 0x8CDF, MAX_TEXTURE_IMAGE_UNITS = 0x8872, MAX_VERTEX_ATTRIBS = 0x8869,
    ALIASED_LINE_WIDTH_RANGE = 0x846E, MAX_TEXTURE_MAX_ANISOTROPY = 0x84FF,
    UNSIGNED_INT_2_10_10_10_REV = 0x8368, TEXTURE_MAX_LEVEL = 0x813D, TEXTURE_MAX_ANISOTROPY = 0x84FE,
    TEXTURE_COMPARE_MODE = 0x884C, DRAW_BUFFER0 = 0x8825, PACK_ALIGNMENT = 0xD05, UNPACK_ALIGNMENT = 0xCF5,
    FRAMEBUFFER_BINDING = 0x8CA6, VIEWPORT = 0xBA2,
}

-- Entry points that may be missing (desktop only); loaded when present.
GL.optional = {
    glPolygonMode = 'void (*)(GLenum, GLenum)',
}

-- Loads every entry point; returns the table or nil plus the first missing name.
function GL.load(platform)
    local gl = { enum = GL.enum }
    for name, signature in pairs(GL.signatures) do
        local address = platform:getProcAddress(name)
        if address == nil or address == ffi.cast('void*', 0) then
            return nil, 'Missing GL entry point: ' .. name
        end
        gl[name] = ffi.cast(signature, address)
    end
    for name, signature in pairs(GL.optional) do
        local address = platform:getProcAddress(name)
        if address ~= nil and address ~= ffi.cast('void*', 0) then
            gl[name] = ffi.cast(signature, address)
        end
    end
    return gl
end

return GL
