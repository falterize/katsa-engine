-- levelEditor scene smoke test: the scene loads, the InputMap actions exist, the fly camera
-- moves from actions, a click on an object selects it and the grid can be toggled.
local Application = require('game.runtime.application')
local Archive = require('source.katsa.core.archive')
local Catalog = require('game.scenes.levelEditor.scripts.builders.catalog')
local LocationIO = require('game.scenes.levelEditor.scripts.io.locationIO')
local LevelFiles = require('game.scenes.levelEditor.scripts.io.levelFiles')

local Module = {}

local ACTIONS = {
    'editorLook', 'editorForward', 'editorBack', 'editorLeft', 'editorRight', 'editorUp',
    'editorDown', 'editorFast', 'editorPick', 'editorAdd', 'editorFocus', 'editorFrameAll',
    'editorToolSelect', 'editorToolMove', 'editorToolRotate', 'editorToolScale',
    'editorToggleGrid', 'editorUndo', 'editorRedo', 'editorSave', 'editorOpen',
}

local function frame(scene)
    scene:update(1 / 60, 1 / 60)
    scene:draw()
end

function Module.run(self)
    local scene = Application.new(self.manager, 'levelEditor')
    scene:load()
    local state = scene.demo
    for _ = 1, 3 do
        frame(scene)
    end
    local map = state.fly.map
    local missing
    for _, name in ipairs(ACTIONS) do
        if not map:hasAction(name) then
            missing = name
        end
    end
    self:check(missing == nil, 'Every editor control is an InputMap action ' .. tostring(missing or ''))
    self:check(#state.level.children == 6 and state.grid.nodes.minor ~= nil, 'The level and the grid are created')

    local camera = state.camera
    self:check(state.viewport:getWorld() == state.world and state.viewport._canvasWidth ~= nil, 'The editor world lives in the Viewport frame and has rendered')
    local vx, vy = state.viewport._x + 4, state.viewport._y + 4
    local lx, ly = state:viewportPoint(vx * state.ui.scale + state.ui.offsetX, vy * state.ui.scale + state.ui.offsetY)
    self:check(lx ~= nil and lx >= 0 and lx < 20 and ly >= 0 and ly < 20, 'Window pixels convert to viewport pixels')
    local before = camera.position[1] * 1000 + camera.position[2] * 100 + camera.position[3]
    map:pressAction('editorLook')
    map:pressAction('editorForward')
    map:update()
    for _ = 1, 10 do
        frame(scene)
    end
    map:releaseAction('editorForward')
    map:releaseAction('editorLook')
    map:update()
    local after = camera.position[1] * 1000 + camera.position[2] * 100 + camera.position[3]
    self:check(math.abs(after - before) > 0.01, 'The fly camera moves from InputMap actions')

    local lightNode = state.ops:create('PointLight3D', { name = 'VizLight', position = { 0, 3, 0 } })
    state.selection:set({ lightNode })
    for _ = 1, 2 do
        frame(scene)
    end
    local lightEntry = state.lightViz.entries[lightNode]
    self:check(lightEntry ~= nil and lightEntry.reach ~= nil and state.lightViz:ownerOf(lightEntry.pick) == lightNode, 'A selected light shows its marker, its reach and can be picked by the marker')
    state.selection:clear()
    state.ops:delete({ lightNode })
    for _ = 1, 2 do
        frame(scene)
    end
    self:check(state.lightViz.entries[lightNode] == nil, 'The visualisation of a deleted light goes away')
    self:check(#state.boxes >= 0 and state.panels.popup ~= nil, 'The shared pop-up panel exists')
    for _ = 1, 2 do
        frame(scene)
    end
    local visibleOutlines = 0
    for _, box in ipairs(state.boxes) do
        visibleOutlines = visibleOutlines + (box.node.visible and 1 or 0)
    end
    self:check(visibleOutlines == state.selection:count(), 'Every selected object has its own outline')
    local Menus = require('game.scenes.levelEditor.scripts.ui.support.menus')
    self:check(#Menus.node(state) > 0 and #Menus.empty(state, { 10, 10 }) > 0 and #Menus.createItems(state) > 0, 'Context and Create menus build their items')
    state.panels.popup:show(Menus.node(state), 100, 100, { width = 200 })
    self:check(state.panels.popup:isOpen(), 'A context menu opens as a pop-up')
    state.panels.popup:close()
    self:check(not state.panels.popup:isOpen(), 'A pop-up closes')
    state:frame(state.level.children)
    for _ = 1, 2 do
        frame(scene)
    end
    local box
    for _, child in ipairs(state.level.children) do
        if child.name == 'Box' then
            box = child
        end
    end
    local x, y = camera:project(box.position)
    state:pick(x, y)
    self:check(state.selection:primary() == box, 'A click on an object selects it')
    state:pick(2, 2)
    self:check(state.selection:count() == 0, 'A click on empty space clears the selection')

    local ops, undo = state.ops, state.undo
    state.selection:set({ box })
    local base = #state.level.children
    ops:duplicate({ box })
    self:check(#state.level.children == base + 1, 'Duplicate adds a copy of the selected object')
    undo:undo()
    self:check(#state.level.children == base, 'Undo removes the duplicate')
    undo:redo()
    self:check(#state.level.children == base + 1, 'Redo brings the duplicate back')
    local copy = state.selection:primary()
    ops:delete({ copy })
    self:check(#state.level.children == base, 'Delete removes the selected object')
    undo:undo()
    self:check(#state.level.children == base + 1, 'Undo of a delete rebuilds the object')
    ops:group({ box })
    local group = state.selection:primary()
    self:check(group.className == 'Node3D' and box.parent == group, 'Group moves the selection under a new Node3D')
    undo:undo()
    self:check(ops:node(ops:idOf(box)).parent == state.level, 'Undo of a group puts the object back')
    local ok = ops:setProperty({ ops:node(ops:idOf(box)) }, 'position', 1, '5')
    self:check(ok and ops:node(ops:idOf(box)).position[1] == 5, 'A property edit goes through the inspector rules')
    undo:undo()
    self:check(ops:node(ops:idOf(box)).position[1] == -3, 'Undo restores the edited property')
    for _ = 1, 2 do
        frame(scene)
    end
    self:check(#state.panels.tree.rows == base + 2 and state.panels.properties.name.visible ~= nil, 'The Workspace tree lists the level and its objects')

    -- Move tool: grab the X arrow and drag it along the screen.
    state:setTool('Move')
    state.selection:set({ box })
    for _ = 1, 2 do
        frame(scene)
    end
    local tool = state.transform
    local pivot = tool.frame.world
    local grab = { pivot[1] + tool.length * 0.6, pivot[2], pivot[3] }
    local gx, gy = camera:project(grab)
    local startX = box.position[1]
    state.snap.enabled = false
    self:check(tool:begin(gx, gy), 'A press on the X arrow starts a move drag')
    local tx, ty = camera:project({ grab[1] + 2, grab[2], grab[3] })
    tool:move(tx, ty)
    tool:finish()
    self:check(math.abs(box.position[1] - (startX + 2)) < 0.05, 'Dragging the X arrow moves the object along X')
    undo:undo()
    self:check(math.abs(box.position[1] - startX) < 1e-6, 'Undo of a move restores the position')
    state:setTool('Select')

    -- Export and import: a cylinder (editor shape) survives, the package is a readable ZIP.
    for _, item in ipairs(Catalog.items()) do
        if item.label == 'Cylinder' then
            item.make(state, { 4, 0, 4 })
        end
    end
    local count = #state.level.children
    local names = {}
    for index, node in ipairs(state.level.children) do
        names[index] = node.name
    end
    local bytes, warnings = LocationIO.export(state)
    local archive = Archive.fromString(bytes, 'export')
    self:check(archive:has('assets/location.lua') and archive:has('main.lua') and archive:has('scripts/loader.lua'), 'An export holds settings, main, the location and the loader')
    self:check(LocationIO.import(state, bytes) == count and #state.level.children == count, 'Importing an export restores the object count')
    do
        local Importer = require('game.scenes.levelEditor.scripts.core.importer')
        for _, item in ipairs(Catalog.items()) do
            if item.label == 'Decal' then
                local decal = item.make(state, { 0, 0, 0 })
                state.selection:set({ decal })
                self:check(Importer.place(state, 'shared://textures/engine/sky/dayCross.png', 'image', 'texture') and decal.image == 'shared://textures/engine/sky/dayCross.png', 'An image can be put on a selected decal')
            end
        end
        do
            local stored = Importer.copy('assets/textures/materials/normal.png', 'textures')
            local url = Importer.url(stored)
            self:check(url:sub(1, 8) == 'scene://' and state.world.resources:canonical(url) == stored, 'Level files are named scene:// inside the editor world')
            local decal
            for _, item in ipairs(Catalog.items()) do
                if item.label == 'Decal' then
                    decal = item.make(state, { 0, 0, 0 })
                end
            end
            state.selection:set({ decal })
            Importer.place(state, stored, 'image', 'texture')
            self:check(decal.image == url, 'An imported image is written as scene://')
            local packed = LocationIO.export(state)
            self:check(Archive.fromString(packed, 'x'):has('assets/' .. url:sub(9)), 'The export packs the scene:// file')
            LocationIO.import(state, packed)
            self:check(katsa.filesystem.getInfo(stored) ~= nil, 'Importing the package restores the file under the level files')
        end
        do
            local box = state.level:find('Box')
            box.position = { box.position[1], 5, box.position[3] }
            state.ops:dropToGround({ box })
            self:check(math.abs(box.position[2] - box.size[2] / 2) < 1e-3, 'Drop to ground puts the bottom of an object on y = 0')
        end
        do
            local counts = {}
            for _, item in ipairs(state.panels.toolbar.items) do
                counts[item.tab] = (counts[item.tab] or 0) + 1
            end
            self:check(counts.view == 11 and counts.assets and counts.assets <= 6, 'Each ribbon tab is built once')
            state.camera.position = { 1, 2, 3 }
            state:resetCamera()
            self:check(state.camera.position[1] == 9 and state.camera.rotation[2] == -135, 'Reset view restores the start camera')
        end
        LevelFiles.createFile('', 'leftover.txt')
        state:newLocation()
        self:check(not katsa.filesystem.getInfo(LevelFiles.full('leftover.txt')), 'A new location starts with empty level files')
        self:check(state.panels.browser.markInto and state.panels.browser.ghost, 'The Files tab has drag feedback widgets')
        count = #state.level.children
        LocationIO.import(state, bytes)
        count = #state.level.children
    end
    local same = true
    for index, node in ipairs(state.level.children) do
        same = same and node.name == names[index]
    end
    self:check(same, 'Importing an export restores names and order')
    self:check(state:saveLocation('smoke') and state:openLocation(LocationIO.pathFor('smoke')), 'A location saves into the save directory and opens again')
    self:check(LocationIO.readRecent()[1] == LocationIO.pathFor('smoke'), 'The saved file is first in the recent list')

    -- The package's own loader builds the same objects from the unpacked files.
    LocationIO.write('editor/pkgtest/assets/location.lua', archive:read('assets/location.lua'))
    local modules = { ['scripts.luaText'] = 'io.luaText', ['scripts.shapes'] = 'builders.shapes' }
    local context = {
        root = 'editor/pkgtest',
        require = function(_, name)
            return require('game.scenes.levelEditor.scripts.' .. modules[name])
        end,
    }
    local loaded = require('game.scenes.levelEditor.scripts.package.loader').create(state.scene, context)
    self:check(#loaded.level.children == count, 'The package loader builds the exported objects')
    loaded.level:destroy()

    -- Reordering by drag and drop: B goes before A, undo restores the order.
    local first, second = state.level.children[1], state.level.children[2]
    self:check(state.ops:reparent({ second }, state.level, first) and state.level.children[1] == second, 'Reparent can place a node before a sibling')
    state.undo:undo()
    self:check(state.level.children[1] == first and state.level.children[2] == second, 'Undo of a reorder restores the order')

    -- Toolbar wraps on a narrow window; the settings file keeps the snap steps.
    local toolbar = state.panels.toolbar
    self:check(toolbar:relayout(700) > toolbar:relayout(1600), 'The toolbar wraps onto more rows in a narrow window')
    state.snap.rotate = 22.5
    state:savePrefs()
    self:check(require('game.scenes.levelEditor.scripts.io.editorSettings').parse(katsa.filesystem.read('editor/settings.lua')).snap.rotate == 22.5, 'Snap steps are saved with the editor settings')
    state.snap.rotate = 15
    toolbar:relayout(scene.root:find('World3D/World2D').width)

    -- Menus build, select all, box select, export and merge import.
    local builtMenus = true
    for _, menu in ipairs(require('game.scenes.levelEditor.scripts.ui.support.menus').list) do
        builtMenus = builtMenus and #menu.items(state) > 0
    end
    self:check(builtMenus, 'Every menu builds its items')
    state:selectAll()
    self:check(state.selection:count() == #state.level.children, 'Select all selects every unlocked object')
    state:frame(state.level.children)
    for _ = 1, 2 do
        frame(scene)
    end
    state.selection:clear()
    local vp = state.viewport
    state:boxSelect(0, 0, vp._canvasWidth, vp._canvasHeight)
    self:check(state.selection:count() > 0, 'A rectangle over the whole view selects objects')
    state.selection:clear()
    local before = #state.level.children
    self:check(state:exportLocation('smokeExport') and katsa.filesystem.getInfo('editor/exports/smokeExport.katsa', 'file') ~= nil, 'Export writes a .katsa into the exports folder')
    self:check(state:importLocation('editor/exports/smokeExport.katsa') and #state.level.children == before * 2, 'Importing a .katsa adds its objects')
    state.undo:undo()
    state:refresh()
    self:check(#state.level.children == before, 'Undo removes an import in one step')

    local lights = 0
    for _, node in ipairs(state.level.children) do
        lights = lights + (node.className == 'PointLight3D' and 1 or 0)
    end
    self:check(lights >= 3 and state.world.environment.shadows.enabled, 'The default level has coloured lights and shadows on')
    local light = state.ops:create('PointLight3D', { name = 'Probe' }, state.level)
    for _ = 1, 3 do
        frame(scene)
    end
    local lit = false
    for _, selected in ipairs(state.world.renderer.lights.selected or {}) do
        lit = lit or selected == light
    end
    self:check(lit, 'A light added to the paused editor world is selected for rendering')
    local picker = state.panels.colorPicker
    picker:show({ key = 'color', value = { 255, 70, 60 } }, 100, 100)
    self:check(picker:isOpen() and picker.scale == 255, 'The colour picker opens on a colour property')
    picker:close()
    self:check(not picker:isOpen(), 'The colour picker closes')

    local group = state.ops:create('Node3D', { name = 'RoundTrip', position = { 4, 0, 4 }, rotation = { 0, 30, 0 } }, state.level)
    state.ops:create('Mesh3D', { name = 'RoundInner', kind = 'cube', position = { 1, 1, 1 }, size = { 1, 2, 3 }, color = { 0.1, 0.2, 0.3, 1 } }, group)
    local ok, bytes, warnings = pcall(LocationIO.export, state)
    self:check(ok and #warnings == 0, 'Saving drops no values')
    self:check(state:saveLocation('roundTrip') and state:openLocation(LocationIO.pathFor('roundTrip')), 'A saved location opens again')
    local function find(parent, name)
        for _, child in ipairs(parent.children) do
            if child.name == name then
                return child
            end
        end
    end
    local inner = find(find(state.level, 'RoundTrip') or { children = {} }, 'RoundInner')
    self:check(
        inner ~= nil and inner.position[1] == 1 and inner.size[3] == 3 and math.abs(inner.color[3] - 0.3) < 1e-6,
        'Position, size and colour survive Save and Open'
    )
    local box = find(state.level, 'Box')
    self:check(box ~= nil and box.position[1] == -3 and box.size[1] == 2, 'Objects keep their transforms after Open')
    local red = find(state.level, 'Red Light')
    self:check(red ~= nil and red.color[1] == 255 and red.range == 14, 'Light colour and range survive Save and Open')

    local Icons = require('game.scenes.levelEditor.scripts.ui.widgets.icons')
    local icons = Icons.names()
    local drawn = #icons > 10
    for _, name in ipairs(icons) do
        drawn = drawn and Icons.image(name) ~= nil
    end
    self:check(drawn, 'Every pixel icon builds an image')
    state.grid:setCell(2)
    state.grid:setMajor(5)
    state.grid:setCount(30)
    self:check(state.grid.cell == 2 and state.grid.step == 10 and state.grid.settings.count == 30, 'The grid cell, major step and size can be changed')
    state:savePrefs()
    self:check(state.prefs.grid.major == 5 and state.prefs.grid.count == 30, 'Grid settings are saved in the preferences')
    state.grid:setCell(1)
    state.grid:setMajor(10)
    state.grid:setCount(60)
    for _ = 1, 2 do
        frame(scene)
    end
    self:check(#state.panels.toolbar.hints > 10, 'Toolbar buttons carry status-bar hints')
    local first = state.ops:placeModel('shared://models/characters/player.glb', { 0, 0, 0 })
    local second = state.ops:placeModel('shared://models/characters/player.glb', { 2, 0, 0 })
    self:check(first ~= nil and second ~= nil and first.name ~= second.name, 'The same model can be placed twice (shared:// reference)')
    local ok, bytes = pcall(LocationIO.export, state)
    self:check(ok and state:saveLocation('sharedModels') and state:openLocation(LocationIO.pathFor('sharedModels')), 'A location with shared:// models saves and opens')
    local tabs = {}
    for _, entry in ipairs(require('game.scenes.levelEditor.scripts.ui.panels.toolbar').TABS) do
        state.panels.toolbar.tab = entry[1]
        state.panels.toolbar:relayout(1280)
        tabs[#tabs + 1] = entry[1]
    end
    state.panels.toolbar.tab = 'home'
    state.panels.toolbar:relayout(1280)
    self:check(#tabs == 4, 'Every ribbon tab lays out')
    local Importer = require('game.scenes.levelEditor.scripts.core.importer')
    local before = #state.level.children
    local imported = Importer.many(state, { 'assets/models/characters/player.glb', 'README.md' })
    local browser = state.panels.browser
    self:check(imported == 2 and #state.level.children == before, 'Import copies files into the level files and places nothing')
    self:check(browser.view == 'level' and browser.levelSelected ~= nil, 'The Assets tab shows where the import went')
    local LevelFiles = require('game.scenes.levelEditor.scripts.io.levelFiles')
    local listed = LevelFiles.list(browser.levelPath)
    self:check(#listed.files >= 1, 'The imported file is listed in its level folder')
    self:check(katsa.dropHandler ~= nil and katsa.dropHandler('README.md') == true, 'Files dropped on the window are imported')
    local Catalog = require('game.scenes.levelEditor.scripts.builders.catalog')
    local made = 0
    for _, entry in ipairs(Catalog.items()) do
        if entry.group == 'Visual' or entry.group == 'Audio' then
            state.selection:set({})
            made = made + (pcall(entry.make, state, { 0, 0, 0 }) and 1 or 0)
        end
    end
    self:check(made >= 6, 'Decal, Surface UI, Billboard, Surface appearance, Particles and Attachment can be created')
    self:check(state:saveLocation('visual') and state:openLocation(LocationIO.pathFor('visual')), 'A level with visual nodes saves and opens')
    local UiText = require('game.scenes.levelEditor.scripts.core.uiText')
    local board
    local function search(node)
        if UiText.supports(node) and not board then
            board = node
        end
        for _, child in ipairs(node.children) do
            search(child)
        end
    end
    search(state.level)
    self:check(board ~= nil and UiText.get(board) ~= '', 'Board text survives Save and Open')

    -- Messages: a log line, a card on the screen and a level guessed from the words.
    local before = #(state.log or {})
    state:notify('Export failed: disk is full')
    state:notify('Saved level')
    frame(scene)
    self:check(#state.log == before + 2 and state.log[before + 1].level == 'error', 'A failure message is logged as an error')
    self:check(#state.panels.toasts.cards >= 2, 'Messages show as cards on the screen')
    state.panels.browser:show('Console')
    frame(scene)
    self:check(state.panels.browser.tab == 'Console', 'The Console tab lists the log')
    local decal = state.world:create('Decal3D', {}, state.level)
    self:check(decal.doubleSided == false, 'A decal is one-sided by default')
    decal.doubleSided = true
    self:check(decal.doubleSided == true, 'A decal can be made double-sided')
    decal:destroy()

    local visible = state.grid.visible
    state.grid:setVisible(not visible)
    self:check(state.grid.nodes.major.visible == (not visible), 'The grid can be toggled')
    scene:release()
end

return Module
