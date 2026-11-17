-- The ImGui toolbar, Explorer and Properties windows, driven through real scenes.
local Application = require('game.runtime.application')
local Tree = require('source.engine.editor.tree.traversal')

local Module = {}

local function frames(host, count)
    for _ = 1, count or 2 do
        host:frame(1 / 60)
    end
end

local function find(scene, className)
    for _, node in ipairs(scene.world._node:getDescendants()) do
        if node.className == className then
            return node
        end
    end
end

function Module.run(self)
    local ImGui = require('source.engine.plugins').require('imgui')
    if not ImGui.available() then
        print('SKIP imguiEditor: ' .. tostring(ImGui.reason()))
        return
    end
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local host = scene:module('editor').imgui

    self:check(
        scene.navigation.visible == false
            and scene.debugButton.visible == false
            and scene.workspace.tab.visible == false,
        'With ImGui the legacy header, Debug button and WS tab are hidden'
    )
    scene:emit('immersion', false)
    self:check(scene.navigation.visible == false, 'Showing the navigation keeps the legacy header hidden')

    host:toggle('explorer')
    host:toggle('properties')
    frames(host)
    self:check(host.open.explorer and host.open.properties, 'The toolbar tools open')
    local state = host.state.explorer
    self:check(#state.rows > 5, 'The Explorer lists the scene tree')

    -- Selecting a node shows its properties; editing goes through Properties.set.
    local light = find(scene, 'Mesh3D') or find(scene, 'Part3D') or scene.world._node:getDescendants()[1]
    host.selection = light
    frames(host)
    local properties = host.state.properties
    self:check(properties.node == light and #properties.fields > 0, 'Properties follows the selection')
    local before = light.name
    local ok = require('source.engine.editor.inspectors.properties').set(
        scene,
        light,
        { key = 'name', kind = 'string', value = before },
        'Renamed'
    )
    frames(host)
    self:check(ok and light.name == 'Renamed', 'A property edit applies through the shared setter')

    -- Every node of the tree draws in Properties without errors.
    local roots, extras = scene.workspace:treeRoots()
    local rows = Tree.rows(roots, {}, nil, '', extras)
    local checked = 0
    for index = 1, #rows, math.max(1, math.floor(#rows / 60)) do
        host.selection = rows[index].node
        frames(host, 1)
        checked = checked + 1
    end
    self:check(checked > 10 and host.open.properties, 'Properties draws for many kinds of nodes')

    host.selection = nil
    frames(host)
    self:check(properties.node == nil, 'Clearing the selection empties Properties')

    -- Presentation scenes hide the toolbar.
    scene:emit('immersion', true)
    self:check(host.hidden == true, 'Hiding the navigation hides the toolbar')
    scene:release()

    -- A scene's collapsible control panel becomes an ImGui window that fires the same handlers.
    local physical = Application.new(self.manager, 'physics2D')
    physical:load()
    local entry = physical.controlPanels and physical.controlPanels[1]
    self:check(
        entry ~= nil and entry.adopted and not entry.panel.visible and not entry.toggle.visible,
        'A collapsible scene panel is adopted by ImGui and the legacy panel and toggle are hidden'
    )
    local button
    for _, child in ipairs(entry.panel.children) do
        if child:isA('Button') then
            button = child
            break
        end
    end
    local presses = 0
    button:connect('press', function()
        presses = presses + 1
    end)
    frames(physical:module('editor').imgui, 3)
    button:emit('press', button, 0, 0, 'imgui')
    self:check(presses == 1 and physical:module('editor').imgui.backend.renderer ~= nil, 'The mirrored panel draws and its buttons keep their handlers')
    -- Tab must not start ImGui keyboard navigation, or the game would lose its keys.
    physical:module('editor').imgui:keypressed('tab')
    frames(physical:module('editor').imgui, 2)
    self:check(not physical:module('editor').imgui:keypressed('w'), 'A Tab press does not make ImGui swallow later game keys')
    physical:release()
    Module.dialogs(self)
end

-- The property dialogs open as ImGui windows and edit the real data.
function Module.dialogs(self)
    local ImGui = require('source.engine.plugins').require('imgui')
    if not ImGui.available() then
        return
    end
    local scene = Application.new(self.manager, 'animationLab')
    scene:load()
    local host = scene:module('editor').imgui
    local ramp
    local function search(node)
        for _, child in ipairs(node.children or {}) do
            if child.className == 'Ramp' and child.points and not ramp then
                ramp = child
            end
            search(child)
        end
    end
    search(scene.root)
    self:check(ramp ~= nil, 'The animation lab has a Ramp to edit')

    local Editors = require('source.plugins.imgui.editors')
    local name, request = Editors.forField(ramp, { kind = 'sequence', key = 'points' })
    local dialog = host:openDialog(name, request)
    frames(host, 3)
    local points = ramp.points
    local count = #points
    dialog.newTime = 0.5
    self:check(#host.dialogs == 1 and dialog.status == '', 'The sequence dialog draws for a Ramp')
    require('source.engine.editor.curves.sequenceModel').insert(points, 0.5, 'Linear')
    dialog.selected = 2
    frames(host, 2)
    self:check(#ramp.points == count + 1, 'The sequence data stays valid after edits')

    local goalName, goalRequest = Editors.forField(ramp, { kind = 'bindings', key = 'bindings' })
    self:check(goalName == 'goals', 'A Ramp bindings field opens the goals dialog')
    host:openDialog(goalName, goalRequest)
    host:openDialog('groups')
    host:openDialog('shaderLayers')
    frames(host, 3)
    self:check(#host.dialogs == 4 and host.open ~= nil, 'Goals, groups and shader layers draw without errors')

    local stops = { { time = 0, color = { 1, 0, 0 } }, { time = 1, color = { 0, 0, 1 } } }
    local holder = { className = 'UIGradient', colorStops = stops, destroyed = false }
    host:openDialog('gradient', { target = holder, field = { key = 'colorStops' } })
    frames(host, 3)
    self:check(#stops == 2 and #host.dialogs == 5, 'The gradient dialog draws stops')

    host.dialogs = {}
    scene:release()
end

return Module
