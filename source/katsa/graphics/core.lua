-- Shared graphics state: GL function table, texture-unit cache, deferred GL object deletion.
local ffi = require('ffi')
local GL = require('source.katsa.graphics.gl')

local Core = { gl = nil, boundTextures = {}, activeUnit = 0, garbage = {}, limits = {} }

function Core.init(platform)
    local gl, message = GL.load(platform)
    if not gl then
        return nil, message
    end
    Core.gl, Core.platform, Core.enum = gl, platform, gl.enum
    Core.es = platform.es and true or false
    Core.boundTextures, Core.activeUnit = {}, 0
    local value = ffi.new('GLint[1]')
    local function int(name)
        gl.glGetIntegerv(gl.enum[name], value)
        return value[0]
    end
    local limits = Core.limits
    limits.texturesize = int('MAX_TEXTURE_SIZE')
    limits.canvasmsaa = math.max(int('MAX_SAMPLES'), 0)
    limits.multicanvas = int('MAX_COLOR_ATTACHMENTS')
    limits.textureunits = int('MAX_TEXTURE_IMAGE_UNITS')
    limits.pointsize = 1
    limits.textureanisotropy = 1
    local range = ffi.new('GLfloat[1]')
    gl.glGetFloatv(gl.enum.MAX_TEXTURE_MAX_ANISOTROPY, range)
    if gl.glGetError() == 0 and range[0] >= 1 then
        limits.textureanisotropy = range[0]
    end
    Core.extensions = {}
    gl.glGetIntegerv(gl.enum.NUM_EXTENSIONS, value)
    for i = 0, value[0] - 1 do
        Core.extensions[ffi.string(gl.glGetStringi(0x1F03, i))] = true
    end
    return gl
end

function Core.rendererInfo()
    local gl = Core.gl
    local version = ffi.string(gl.glGetString(gl.enum.VERSION))
    return Core.es and 'OpenGL ES' or 'OpenGL', version, ffi.string(gl.glGetString(gl.enum.VENDOR)),
        ffi.string(gl.glGetString(gl.enum.RENDERER))
end

-- Framebuffer binding cache. `nil` means unknown and forces the next bind.
Core.boundFramebuffer = nil
function Core.bindFramebuffer(id)
    if Core.boundFramebuffer ~= id then
        Core.gl.glBindFramebuffer(Core.enum.FRAMEBUFFER, id)
        Core.boundFramebuffer = id
    end
end
function Core.framebufferChanged()
    Core.boundFramebuffer = nil
    if Core.restoreFramebuffer then
        Core.restoreFramebuffer()
    end
end
function Core.forgetFramebuffer(id)
    if Core.boundFramebuffer == id then
        Core.boundFramebuffer = nil
    end
    if Core.onFramebufferDeleted then
        Core.onFramebufferDeleted(id)
    end
end

-- Single VAO: element buffer binding and attribute arrays are tracked here.
Core.boundElementBuffer = nil
function Core.bindElementBuffer(id)
    if Core.boundElementBuffer ~= id then
        Core.gl.glBindBuffer(Core.enum.ELEMENT_ARRAY_BUFFER, id)
        Core.boundElementBuffer = id
    end
end

Core.enabledAttributes = {}
function Core.setEnabledAttributes(wanted)
    local gl, enabled = Core.gl, Core.enabledAttributes
    for location in pairs(enabled) do
        if not wanted[location] then
            gl.glDisableVertexAttribArray(location)
            enabled[location] = nil
        end
    end
    for location in pairs(wanted) do
        enabled[location] = true
    end
end

Core.currentProgram = nil
function Core.useProgram(program)
    if Core.currentProgram ~= program then
        Core.gl.glUseProgram(program)
        Core.currentProgram = program
    end
end

function Core.bindTexture(unit, id)
    local gl = Core.gl
    if Core.activeUnit ~= unit then
        gl.glActiveTexture(gl.enum.TEXTURE0 + unit)
        Core.activeUnit = unit
    end
    if Core.boundTextures[unit] ~= id then
        gl.glBindTexture(gl.enum.TEXTURE_2D, id)
        Core.boundTextures[unit] = id
    end
end

-- Binds without disturbing unit 0's cached binding (used while editing a texture).
function Core.bindForEdit(id)
    Core.bindTexture(0, id)
end

function Core.forgetTexture(id)
    for unit, bound in pairs(Core.boundTextures) do
        if bound == id then
            Core.boundTextures[unit] = nil
        end
    end
end

-- GL objects are deleted on the main thread at a safe point, never inside a GC finalizer.
function Core.defer(resources)
    Core.garbage[#Core.garbage + 1] = resources
end

local function deleteResources(res)
    local gl = Core.gl
    if not gl then
        return
    end
    local one = ffi.new('GLuint[1]')
    if res.texture then
        Core.forgetTexture(res.texture)
        one[0] = res.texture
        gl.glDeleteTextures(1, one)
    end
    if res.renderbuffers then
        for _, id in ipairs(res.renderbuffers) do
            one[0] = id
            gl.glDeleteRenderbuffers(1, one)
        end
    end
    for _, id in ipairs(res.fbos or {}) do
        one[0] = id
        Core.forgetFramebuffer(id)
        gl.glDeleteFramebuffers(1, one)
    end
    if res.buffers then
        for _, id in ipairs(res.buffers) do
            one[0] = id
            gl.glDeleteBuffers(1, one)
        end
    end
    if res.program then
        if Core.currentProgram == res.program then
            Core.currentProgram = nil
        end
        gl.glDeleteProgram(res.program)
    end
    if Core.onDelete then
        Core.onDelete(res)
    end
end
Core.deleteResources = deleteResources

function Core.collect()
    local garbage = Core.garbage
    if #garbage == 0 then
        return
    end
    Core.garbage = {}
    for _, res in ipairs(garbage) do
        deleteResources(res)
    end
end

-- Attaches a finalizer that queues `res` for deletion when the Lua object is collected.
function Core.track(object, res)
    object._res = res
    object._sentinel = ffi.gc(ffi.new('char[1]'), function()
        if not res.released then
            res.released = true
            Core.defer(res)
        end
    end)
end

function Core.release(object)
    local res = object._res
    if res and not res.released then
        res.released = true
        deleteResources(res)
        return true
    end
    return false
end

return Core
