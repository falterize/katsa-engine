-- ImGui integration of the scene: the engine's tool windows (Stats, Debug, ...) and ImGuiLayer
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
    -- The old Tools panel and button are gone with ImGui.
    self.toolsPanel.visible = false
    self.toolsButton.visible = false
    -- The ImGui toolbar replaces the whole Navigation header, the Debug button and the WS tab.
    self.navigationVisible = self.navigation.visible
    self:syncLegacyNavigation()
    for _, entry in ipairs(self.controlPanels or {}) do
        self:adoptControlPanel(entry)
    end
    return true
end

-- A control panel registered through ui/widgets/collapsible becomes an ImGui window; the engine
-- panel and its toggle stay hidden and keep owning the behaviour. Does nothing without ImGui.
function Methods:adoptControlPanel(entry)
    if not self.imgui or entry.adopted then
        return
    end
    entry.adopted = true
    if entry.onAdopt then
        entry.onAdopt()
    end
    if entry.nodes then
        -- Loose controls move into a hidden holder, keeping their own visibility flags.
        local ui = self.root:find('World3D/World2D')
        entry.panel = ui:container({ name = entry.title .. 'Controls', visible = false }, ui.content)
        for _, node in ipairs(entry.nodes) do
            node.parent = entry.panel
        end
        return
    end
    entry.startOpen = entry.toggle == nil or entry.panel.visible ~= false
    entry.panel.visible = false
    if entry.toggle then
        entry.toggle.visible = false
    end
end

-- With ImGui the legacy header, Debug button and WS tab stay hidden; the toolbar reads
-- `navigationVisible` instead.
function Methods:syncLegacyNavigation()
    self.navigation.visible = false
    if self.debugButton then
        self.debugButton.visible = false
    end
    if self.workspace then
        self.workspace.tab.visible = false
    end
end

-- Shows a node in the editor: the ImGui Explorer and Properties windows, or the legacy Workspace
-- panel without ImGui.
function Methods:inspect(node)
    if self.imgui then
        self.imgui.selection = node
        self.imgui.open.explorer, self.imgui.open.properties = true, true
    else
        self.workspace:toggle(true)
        self.workspace:select(node)
    end
end

-- Opens the interaction-groups or shader-layers editor (ImGui window, or the legacy popup
-- without ImGui).
function Methods:openEditor(name)
    if self.imgui then
        self.imgui:openDialog(name)
    elseif name == 'groups' then
        require('source.engine.editor.panels.groupEditor').open(self.workspace)
    elseif name == 'shaderLayers' then
        self.workspace.selected = self.pixel or self.workspace.selected
        require('source.engine.editor.panels.shaderLayers').open(self.workspace)
    end
end

-- F2: opens or closes the editor windows.
function Methods:toggleEditor()
    if self.imgui then
        local open = not (self.imgui.open.explorer and self.imgui.open.properties)
        self.imgui.open.explorer, self.imgui.open.properties = open, open
    else
        self.workspace:toggle()
    end
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
