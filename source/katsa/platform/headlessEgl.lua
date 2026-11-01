-- Headless EGL platform: an offscreen (surfaceless) context for dedicated servers, CI and tests.
-- It never opens a window. Desktop GL 3.3 core and OpenGL ES 3.0 are both available so the same
-- shader translation can be validated for either target.
local ffi = require('ffi')

ffi.cdef([[
typedef void* EGLDisplay; typedef void* EGLConfig; typedef void* EGLContext; typedef void* EGLSurface;
typedef int32_t EGLint; typedef unsigned int EGLBoolean; typedef unsigned int EGLenum;
EGLDisplay eglGetPlatformDisplay(EGLenum platform, void* native, const intptr_t* attribs);
EGLBoolean eglInitialize(EGLDisplay, EGLint*, EGLint*);
EGLBoolean eglTerminate(EGLDisplay);
EGLBoolean eglBindAPI(EGLenum api);
EGLBoolean eglChooseConfig(EGLDisplay, const EGLint*, EGLConfig*, EGLint, EGLint*);
EGLContext eglCreateContext(EGLDisplay, EGLConfig, EGLContext, const EGLint*);
EGLBoolean eglDestroyContext(EGLDisplay, EGLContext);
EGLBoolean eglMakeCurrent(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
void* eglGetProcAddress(const char*);
EGLint eglGetError(void);
]])

local Headless = {}
Headless.__index = Headless

local EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
local EGL_OPENGL_API, EGL_OPENGL_ES_API = 0x30A2, 0x30A0
local EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_OPENGL_ES3_BIT = 0x3040, 0x8, 0x40
local EGL_CONTEXT_MAJOR, EGL_CONTEXT_MINOR = 0x3098, 0x30FB
local EGL_CONTEXT_PROFILE, EGL_CORE_BIT = 0x30FD, 0x1
local EGL_NONE = 0x3038

local egl

local function library()
    if not egl then
        egl = ffi.load('libEGL.so.1')
    end
    return egl
end

-- Returns a headless platform, or nil and a reason when EGL or the context is unavailable.
function Headless.new(target)
    target = target or 'desktop'
    assert(target == 'desktop' or target == 'es', 'Unknown headless target: ' .. tostring(target))
    local ok, lib = pcall(library)
    if not ok then
        return nil, 'EGL is not available: ' .. tostring(lib)
    end
    local display = lib.eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, nil, nil)
    if display == nil then
        return nil, 'No surfaceless EGL display'
    end
    local major, minor = ffi.new('EGLint[1]'), ffi.new('EGLint[1]')
    if lib.eglInitialize(display, major, minor) == 0 then
        return nil, 'eglInitialize failed: 0x' .. bit.tohex(lib.eglGetError(), 4)
    end
    local es = target == 'es'
    lib.eglBindAPI(es and EGL_OPENGL_ES_API or EGL_OPENGL_API)
    local attributes = ffi.new(
        'EGLint[3]',
        EGL_RENDERABLE_TYPE,
        es and EGL_OPENGL_ES3_BIT or EGL_OPENGL_BIT,
        EGL_NONE
    )
    local config, count = ffi.new('EGLConfig[1]'), ffi.new('EGLint[1]')
    -- A surfaceless display usually exposes no config; EGL_KHR_no_config_context accepts nil.
    local chosen = nil
    if lib.eglChooseConfig(display, attributes, config, 1, count) ~= 0 and count[0] > 0 then
        chosen = config[0]
    end
    local context
    if es then
        local contextAttributes =
            ffi.new('EGLint[5]', EGL_CONTEXT_MAJOR, 3, EGL_CONTEXT_MINOR, 0, EGL_NONE)
        context = lib.eglCreateContext(display, chosen, nil, contextAttributes)
    else
        local contextAttributes = ffi.new(
            'EGLint[7]',
            EGL_CONTEXT_MAJOR,
            3,
            EGL_CONTEXT_MINOR,
            3,
            EGL_CONTEXT_PROFILE,
            EGL_CORE_BIT,
            EGL_NONE
        )
        context = lib.eglCreateContext(display, chosen, nil, contextAttributes)
    end
    if context == nil then
        return nil, 'eglCreateContext failed: 0x' .. bit.tohex(lib.eglGetError(), 4)
    end
    if lib.eglMakeCurrent(display, nil, nil, context) == 0 then
        return nil, 'eglMakeCurrent failed: 0x' .. bit.tohex(lib.eglGetError(), 4)
    end
    return setmetatable({
        target = target,
        display = display,
        context = context,
        eglVersion = major[0] .. '.' .. minor[0],
    }, Headless)
end

function Headless:getProcAddress(name)
    local pointer = library().eglGetProcAddress(name)
    return pointer ~= nil and pointer or nil
end

function Headless:close()
    if self.context then
        local lib = library()
        lib.eglMakeCurrent(self.display, nil, nil, nil)
        lib.eglDestroyContext(self.display, self.context)
        lib.eglTerminate(self.display)
        self.context = nil
    end
end

return Headless
