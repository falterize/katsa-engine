-- ImGui integration of the scene: the engine's tool windows (Stats, Scene tools) and ImGuiLayer
-- nodes. Without the native library the scene keeps the legacy Stats panel and Tools button.
local Methods = {}

function Methods:attachImGui()
    local ImGui = require('source.engine.plugins').require('imgui')
    local host, reason = ImGui.attach(self)
    if not host then
        self.imguiReason = reason
        return false
    end
    self.imgui = host
    -- The old Tools panel is replaced by the Scene tools window (F8, F10 menu bar).
    self.toolsPanel.visible = false
    self.toolsButton.visible = false
    return true
end

-- Runs the ImGui frame after the scene and its UI have been drawn.
function Methods:drawImGui()
    local host = self.imgui
    if host then
        host:frame(katsa.timer.getDelta())
        host:draw()
    end
end

function Methods:releaseImGui()
    if self.imgui then
        self.imgui:release()
        self.imgui = nil
    end
end

return Methods
