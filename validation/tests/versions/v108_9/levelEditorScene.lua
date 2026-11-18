-- levelEditor scene smoke test: the scene loads, the InputMap actions exist, the fly camera
-- moves from actions, a click on an object selects it and the grid can be toggled.
local Application = require('game.runtime.application')
local Archive = require('source.katsa.core.archive')
local Catalog = require('game.scenes.levelEditor.scripts.builders.catalog')
local LocationIO = require('game.scenes.levelEditor.scripts.io.locationIO')

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
    self:check(#state.level.children == 3 and state.grid.nodes.minor ~= nil, 'The level and the grid are created')

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
    ops:duplicate({ box })
    self:check(#state.level.children == 4, 'Duplicate adds a copy of the selected object')
    undo:undo()
    self:check(#state.level.children == 3, 'Undo removes the duplicate')
    undo:redo()
    self:check(#state.level.children == 4, 'Redo brings the duplicate back')
    local copy = state.selection:primary()
    ops:delete({ copy })
    self:check(#state.level.children == 3, 'Delete removes the selected object')
    undo:undo()
    self:check(#state.level.children == 4, 'Undo of a delete rebuilds the object')
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
    self:check(#state.panels.tree.rows == 5 and state.panels.properties.name.visible ~= nil, 'The Workspace tree lists the level and its objects')

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

    -- Menus build, select all, box select, play-test restore, export and merge import.
    local builtMenus = true
    for _, menu in ipairs(require('game.scenes.levelEditor.scripts.ui.menus').list) do
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
    state:togglePlay()
    local running = state.playing and state.root3D.timeScale == 1
    state.level.children[1].position = { 50, 50, 50 }
    state:togglePlay()
    self:check(running and not state.playing and #state.level.children == before and state.level.children[1].position[1] ~= 50, 'Play-test restores the level when it stops')
    self:check(state:exportLocation('smokeExport') and katsa.filesystem.getInfo('editor/exports/smokeExport.katsa', 'file') ~= nil, 'Export writes a .katsa into the exports folder')
    self:check(state:importLocation('editor/exports/smokeExport.katsa') and #state.level.children == before * 2, 'Importing a .katsa adds its objects')
    state.undo:undo()
    state:refresh()
    self:check(#state.level.children == before, 'Undo removes an import in one step')

    local visible = state.grid.visible
    state.grid:setVisible(not visible)
    self:check(state.grid.nodes.major.visible == (not visible), 'The grid can be toggled')
    scene:release()
end

return Module
