-- The editor of the example scenes: the ImGui host (toolbar, Explorer, Properties, tool windows,
-- scene control panels, property dialogs) and the legacy Workspace panel that stands in when the
-- ImGui library is unavailable. Scenes reach it only as `scene:module('editor')`; without the
-- module (or without ImGui) they keep working.
local ipairs = require('source.engine.math.array').ipairs

local Editor = { name = 'editor' }
Editor.__index = Editor

function Editor.install(scene)
    return setmetatable({ scene = scene }, Editor)
end

-- Scene API -----------------------------------------------------------------------------------

-- Shows a node in the editor: the ImGui Explorer and Properties windows, or the legacy Workspace
-- panel without ImGui.
function Editor:inspect(node)
    if self.imgui then
        self.imgui.selection = node
        self.imgui.open.explorer, self.imgui.open.properties = true, true
    else
        self.scene.workspace:toggle(true)
        self.scene.workspace:select(node)
    end
end

-- Opens the interaction-groups or shader-layers editor (ImGui window, or the legacy popup
-- without ImGui). `node` is the node the shader-layers popup starts from.
function Editor:openEditor(name, node)
    local workspace = self.scene.workspace
    if self.imgui then
        self.imgui:openDialog(name)
    elseif name == 'groups' then
        require('source.engine.editor.panels.groupEditor').open(workspace)
    elseif name == 'shaderLayers' then
        workspace.selected = node or workspace.selected
        require('source.engine.editor.panels.shaderLayers').open(workspace)
    end
end

-- F2: opens or closes the editor windows.
function Editor:toggleEditor()
    if self.imgui then
        local open = not (self.imgui.open.explorer and self.imgui.open.properties)
        self.imgui.open.explorer, self.imgui.open.properties = open, open
    else
        self.scene.workspace:toggle()
    end
end

-- A control panel registered through ui/widgets/collapsible becomes an ImGui window; the engine
-- panel and its toggle stay hidden and keep owning the behaviour. Does nothing without ImGui.
function Editor:adoptControlPanel(entry)
    if not self.imgui or entry.adopted then
        return
    end
    entry.adopted = true
    if entry.onAdopt then
        entry.onAdopt()
    end
    if entry.nodes then
        -- Loose controls move into a hidden holder, keeping their own visibility flags.
        local ui = self.scene.root:find('World3D/World2D')
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

-- Hooks ---------------------------------------------------------------------------------------

function Editor:presentation()
    local scene = self.scene
    local ImGui = require('source.engine.plugins').require('imgui')
    local host, reason = ImGui.attach(scene)
    if not host then
        self.reason = reason
        return
    end
    self.imgui = host
    local presentation = scene.settings.presentation
    host.hidden = presentation ~= nil and presentation.navigation == false
    scene:emit('imguiAttached', host)
    for _, entry in ipairs(scene.controlPanels or {}) do
        self:adoptControlPanel(entry)
    end
end

function Editor:ready()
    local scene = self.scene
    scene.workspace = require('source.engine.editor.workspace').new(scene)
    local presentation = scene.settings.presentation
    if self.imgui or presentation and presentation.navigation == false then
        scene.workspace.tab.visible = false
    end
end

function Editor:controlPanel(entry)
    self:adoptControlPanel(entry)
end

function Editor:toggleDebug()
    if self.imgui then
        self.imgui:toggle('debug')
        return true
    end
    return false
end

function Editor:immersion(captured)
    local scene = self.scene
    if self.imgui then
        self.imgui.hidden = captured
    elseif scene.workspace then
        scene.workspace.tab.visible = not captured
    end
    if captured and scene.workspace then
        scene.workspace:toggle(false)
    end
end

function Editor:resize()
    if self.scene.workspace then
        self.scene.workspace:resize()
    end
end

function Editor:update(dt)
    self.scene.workspace:update(dt)
end

function Editor:pointerpressed(id, x, y)
    return self.imgui ~= nil and self.imgui:pointerpressed(id, x, y)
end

function Editor:pointermoved(id, x, y)
    return self.imgui ~= nil and self.imgui:pointermoved(id, x, y)
end

function Editor:pointerreleased(id, x, y)
    if self.imgui then
        self.imgui:pointerreleased(id, x, y)
    end
end

function Editor:keypressed(key)
    local scene = self.scene
    if self.imgui and self.imgui:keypressed(key) then
        return true
    end
    -- The runtime's menu key goes to gameplay input, not to the Workspace.
    if
        scene.input.menuKey
        and key == scene.input.menuKey
        and not require('source.engine.ui.widgets.textFocus').current
    then
        return false
    end
    return scene.workspace:keypressed(key)
end

function Editor:keyUnhandled(key)
    if key == 'f2' then
        self:toggleEditor()
        return true
    end
    return false
end

function Editor:keyreleased(key)
    if self.imgui then
        self.imgui:keyreleased(key)
    end
end

function Editor:textinput(text)
    if self.imgui and self.imgui:textinput(text) then
        return true
    end
    if self.scene.workspace.editing then
        self.scene.workspace:textinput(text)
        return true
    end
    return false
end

function Editor:mousebutton(button, down)
    if self.imgui then
        self.imgui:mousebutton(button, down)
    end
end

function Editor:wheelmoved(x, y)
    return self.imgui ~= nil and self.imgui:wheelmoved(x, y)
end

-- Typing in a Workspace field or an open popup pauses gameplay input.
function Editor:blocksInput()
    local workspace = self.scene.workspace
    return workspace ~= nil and (workspace.editing or workspace.popup) and true or false
end

function Editor:capturesInput()
    local workspace = self.scene.workspace
    return workspace ~= nil and workspace.opened == true
end

function Editor:pause()
    self.scene.workspace:cancelEdit()
end

Editor.exit = Editor.pause

-- Runs the ImGui frame after the scene and its UI have been drawn.
function Editor:afterUI()
    local host = self.imgui
    if host then
        host:frame(katsa.timer.getDelta())
        host:draw()
    end
end

function Editor:release()
    if self.imgui then
        self.imgui:release()
        self.imgui = nil
    end
end

return Editor
