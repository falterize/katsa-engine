-- ImGui for katsa: Dear ImGui (through cimgui) bound with the LuaJIT FFI. The plugin is
-- self-contained: sources in vendor/, binaries in native/, bindings in binding/, the katsa backend
-- (input, textures, rendering) in backend/ and the engine's own tool windows in tools/.
-- See docs/guides/development/imgui.md; the same layout is the template for binding any other
-- library written in another language.
--
--   local ImGui = require('source.engine.plugins').require('imgui')
--   local gui, reason = ImGui.new()       -- nil when the native library is not available
local Backend = require('./backend')
local Library = require('./binding.library')
local Host = require('./host')

local ImGui = {}

-- True when the native library for this platform loads.
function ImGui.available()
    return Library.load() ~= nil
end

-- Why the library is unavailable (nil when it loads).
function ImGui.reason()
    local _, reason = Library.load()
    return reason
end

ImGui.new = Backend.new
-- The scene integration: tool windows, ImGuiLayer nodes and input routing.
ImGui.attach = Host.attach

return ImGui
