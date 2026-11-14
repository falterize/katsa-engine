return {
    name = 'imgui',
    title = 'ImGui',
    version = '1.0.0',
    description = 'Dear ImGui 1.93 (docking) through cimgui and the LuaJIT FFI: an immediate-mode '
        .. 'toolkit for developer tools, the ImGuiLayer node and the engine tool windows (Stats, '
        .. 'Scene tools). Needs the native library of the platform (native/).',
    requires = {},
    nodes = {
        ImGuiLayer = './nodes.imGuiLayer',
    },
}
