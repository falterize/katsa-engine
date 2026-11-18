-- levelEditor scene smoke test: the scene loads, the InputMap actions exist, the fly camera
-- moves from actions, a click on an object selects it and the grid can be toggled.
local Application = require('game.runtime.application')

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

    local camera = state.scene.camera
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

    local visible = state.grid.visible
    state.grid:setVisible(not visible)
    self:check(state.grid.nodes.major.visible == (not visible), 'The grid can be toggled')
    scene:release()
end

return Module
