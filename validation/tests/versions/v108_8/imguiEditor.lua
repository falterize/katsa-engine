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
    local host = scene.imgui

    self:check(
        scene.navigation.visible == false
            and scene.debugButton.visible == false
            and scene.workspace.tab.visible == false,
        'With ImGui the legacy header, Debug button and WS tab are hidden'
    )
    scene:setNavigationVisible(true)
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
    scene:setNavigationVisible(false)
    self:check(scene.navigationVisible == false, 'Hiding the navigation hides the toolbar')
    scene:release()
end

return Module
