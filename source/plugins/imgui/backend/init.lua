local bit = require('bit')
local Library = require('../binding.library')
local Api = require('../binding.api')
local Input = require('./input')
local Renderer = require('./renderer')

-- One ImGui context bound to katsa: input in, draw data out.
--
--   local gui = Backend.new()              -- nil, reason when the native library is missing
--   gui:frame(dt, function(ig) ... end)    -- once per frame: NewFrame, your windows, Render
--   gui:draw()                             -- after the scene and the UI
--   gui:pointerpressed(...)                -- event hooks, return true when ImGui took the event
local Backend = {}
Backend.__index = Backend

-- options.docking: dockable windows. options.scale: UI scale (fonts and spacing).
function Backend.new(options)
    options = options or {}
    local library, reason = Library.load()
    if not library then
        return nil, reason
    end
    local C = library.C
    local self = setmetatable({ library = library, C = C, ig = Api.new(library) }, Backend)
    self.context = C.igCreateContext(nil)
    -- CreateContext only makes the new context current when none is; another scene may own one.
    C.igSetCurrentContext(self.context)
    self.io = C.igGetIO_Nil()
    local io = self.io
    io.IniFilename = nil
    io.LogFilename = nil
    io.ConfigFlags = bit.bor(io.ConfigFlags, C.ImGuiConfigFlags_NavEnableKeyboard)
    if options.docking then
        io.ConfigFlags = bit.bor(io.ConfigFlags, C.ImGuiConfigFlags_DockingEnable)
    end
    io.BackendFlags = bit.bor(io.BackendFlags, C.ImGuiBackendFlags_RendererHasTextures)
    C.igGetStyle().FontScaleMain = options.scale or 1
    C.igStyleColorsDark(nil)
    self.input = Input.new(C, io)
    self.renderer = Renderer.new(C)
    self.frames = 0
    return self
end

-- Runs one ImGui frame. `build(ig)` creates the windows; `dt` is the real frame time.
function Backend:frame(dt, build)
    local C, io = self.C, self.io
    -- Another scene's context may have been created or destroyed since the last frame.
    C.igSetCurrentContext(self.context)
    local width, height = katsa.graphics.getDimensions()
    io.DisplaySize.x, io.DisplaySize.y = width, height
    io.DeltaTime = math.max(dt, 1 / 1000)
    local scale = katsa.graphics.getDPIScale()
    io.DisplayFramebufferScale.x, io.DisplayFramebufferScale.y = scale, scale
    C.igNewFrame()
    if build then
        build(self.ig)
    end
    C.igRender()
    self.frames = self.frames + 1
    -- A text field opens the on-screen keyboard on touch devices.
    if katsa.keyboard and katsa.keyboard.setTextInput then
        local wanted = io.WantTextInput
        if wanted ~= self.textInput then
            self.textInput = wanted
            katsa.keyboard.setTextInput(wanted)
        end
    end
end

-- Draws the last frame into the current canvas.
function Backend:draw()
    self.renderer:draw(self.C.igGetDrawData())
end

function Backend:wantsMouse()
    return self.io.WantCaptureMouse
end

function Backend:wantsKeyboard()
    return self.io.WantCaptureKeyboard
end

for _, name in ipairs({ 'pointerpressed', 'pointermoved', 'pointerreleased', 'mousebutton', 'wheelmoved', 'key', 'textinput' }) do
    Backend[name] = function(self, ...)
        return self.input[name](self.input, ...)
    end
end

function Backend:release()
    if self.context then
        self.renderer:release()
        self.C.igDestroyContext(self.context)
        self.context = nil
    end
end

return Backend
