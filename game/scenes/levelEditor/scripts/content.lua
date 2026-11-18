-- Level editor composition: world lighting, the Level root that owns every placed object, the
-- fly camera, grid, selection and the editor's per-frame commands. Controls are InputMap actions.
local Bounds = require('./core.bounds')
local EditorInput = require('./input.editorInput')
local FlyCamera = require('./view.flyCamera')
local Grid = require('./view.grid')
local LocationIO = require('./io.locationIO')
local Ops = require('./core.levelOps')
local Picking = require('source.engine.world.picking')
local Selection = require('./core.selection')
local Snap = require('./core.snap')
local SelectionBox = require('./view.selectionBox')
local TransformTool = require('./tools.transformTool')
local Undo = require('./core.undo')

local Content = {}
Content.__index = Content

local TOOLS = { 'Select', 'Move', 'Rotate', 'Scale' }

function Content.new(scene)
    local settings = scene.settings.editor
    local world = scene.world
    local environment = world.environment
    environment.debug.gizmos.enabled = true -- lights and cameras show their engine gizmos
    environment.shadows.enabled = false
    environment.ambient = { 130, 136, 150 }
    environment.sky.enabled = true
    world:create('DirectionalLight3D', {
        name = 'EditorSun',
        rotation = { 50, 35, 0 },
        color = { 255, 244, 222 },
        brightness = 1.1,
    })

    local self = setmetatable({ scene = scene, settings = settings }, Content)
    self.level = world:create('Node3D', { name = 'Level' })
    self.selection = Selection.new()
    self.undo = Undo.new()
    self.treeVersion = 0
    self.tool, self.space, self.pivotMode = 'Select', 'World', 'Center'
    self.snap = {
        enabled = true,
        move = settings.snap.move,
        rotate = settings.snap.rotate,
        scale = settings.snap.scale,
    }
    self.grid = Grid.new(world, nil, settings.grid)
    self.box = SelectionBox.new(world)
    self.ops = Ops.new(self)
    self:seed()
    self.ops:adopt(self.level)
    self.recent = LocationIO.readRecent()
    self.savedVersion = 0

    local camera = scene.camera
    camera.near, camera.far, camera.fov = 0.05, 2000, settings.fov
    camera.drawDistance = 2000
    camera.position = { 9, 7, 9 }
    camera.rotation = { -25, -135, 0 }
    scene.input = EditorInput.new(scene, self)
    self.fly = FlyCamera.new(camera, scene.input.map, settings)
    self.transform = TransformTool.new(self)
    return self
end

-- A few starter objects so a fresh editor is not an empty void.
function Content:seed()
    local world = self.scene.world
    local function mesh(name, kind, position, size, color)
        return world:create('Mesh3D', {
            name = name,
            kind = kind,
            position = position,
            size = size,
            color = color,
        }, self.level)
    end
    mesh('Floor', 'cube', { 0, -0.25, 0 }, { 20, 0.5, 20 }, { 0.55, 0.58, 0.62, 1 })
    mesh('Box', 'cube', { -3, 1, 2 }, { 2, 2, 2 }, { 0.85, 0.35, 0.3, 1 })
    mesh('Ball', 'sphere', { 2.5, 1, -1 }, { 2, 2, 2 }, { 0.3, 0.6, 0.9, 1 })
end

-- The direct child of Level that contains a picked mesh (a group when it is inside one).
-- A point in front of the camera for new objects: where the view centre meets the ground, or
-- eight units ahead; snapped to the move step when snapping is on.
function Content:placement()
    local camera = self.scene.camera
    local ray = self.transform:ray((camera.width or 1280) / 2, (camera.height or 720) / 2)
    local point = Snap.planePoint(ray[1], ray[2], { 0, 0, 0 }, { 0, 1, 0 })
    if not point or (point[1] - ray[1][1]) ^ 2 + (point[3] - ray[1][3]) ^ 2 > 60 ^ 2 then
        point = {
            ray[1][1] + ray[2][1] * 8,
            ray[1][2] + ray[2][2] * 8,
            ray[1][3] + ray[2][3] * 8,
        }
    end
    if self.snap.enabled then
        point[1], point[3] = Snap.value(point[1], self.snap.move), Snap.value(point[3], self.snap.move)
    end
    return { point[1], point[2], point[3] }
end

-- Removes every object from the Level (used before a file is opened or a new one started).
function Content:clearLevel()
    self.selection:clear()
    for index = #self.level.children, 1, -1 do
        local node = self.level.children[index]
        self.ops:forget(node)
        node:destroy()
    end
    self.undo:clear()
    self:refresh()
end

-- Saves under `name` (or the current file). Returns true or false plus a message.
function Content:saveLocation(name)
    local path = LocationIO.pathFor(name or self.fileName or 'untitled')
    local ok, bytes, warnings = pcall(LocationIO.export, self)
    if not ok then
        self:notify('Save failed: ' .. tostring(bytes))
        return false
    end
    local written, message = LocationIO.write(path, bytes)
    if not written then
        self:notify('Save failed: ' .. tostring(message))
        return false
    end
    self.fileName, self.savedVersion = LocationIO.nameOf(path), self.undo.version
    self.recent = LocationIO.remember(path)
    self:notify(('Saved %s%s'):format(path, #warnings > 0 and ('  (' .. warnings[1] .. ')') or ''))
    return true
end

-- Opens a `.katsa` from the virtual file system (the save directory or a project folder).
function Content:openLocation(path)
    local bytes = katsa.filesystem.read(path)
    if not bytes then
        self:notify('Cannot read ' .. path)
        LocationIO.forget(path)
        return false
    end
    local count, message = LocationIO.import(self, bytes)
    if not count then
        self:notify(tostring(message))
        return false
    end
    self.fileName, self.savedVersion = LocationIO.nameOf(path), self.undo.version
    self.recent = LocationIO.remember(path)
    self:notify(('Opened %s (%d objects)'):format(path, count))
    return true
end

-- Writes the autosave when something changed since the last one.
function Content:autosave(dt)
    self.autosaveTimer = (self.autosaveTimer or 0) + dt
    if self.autosaveTimer < (self.settings.autosaveSeconds or 60) then
        return
    end
    self.autosaveTimer = 0
    if self.autosavedVersion == self.undo.version then
        return
    end
    local ok, bytes = pcall(LocationIO.export, self)
    if ok and LocationIO.write(LocationIO.AUTOSAVE, bytes) then
        self.autosavedVersion = self.undo.version
    end
end

function Content:isDirty()
    return self.undo.version ~= (self.savedVersion or 0)
end

function Content:overUI()
    local ui = self.scene.root:find('World3D/World2D')
    return ui ~= nil and ui:hit(katsa.mouse.getX(), katsa.mouse.getY()) ~= nil
end

function Content:levelChild(object)
    local node = object
    while node and node.parent ~= self.level do
        node = node.parent
    end
    return node
end

function Content:pick(x, y)
    local scene, map = self.scene, self.fly.map
    local hit = Picking.raycast(scene.world, scene.camera, x, y)
    local node = hit and self:levelChild(hit)
    if node and self.ops:isLocked(node) then
        node = nil
    end
    local add = map:isDown('editorAdd')
    if not node then
        if not add then
            self.selection:clear()
        end
    elseif add then
        self.selection:toggle(node)
    else
        self.selection:set({ node })
    end
end

function Content:frame(nodes)
    local center, radius = Bounds.sphere(nodes)
    if center then
        self.fly:frame(center, radius)
    end
end

function Content:setTool(name)
    self.tool = name
    for tool, button in pairs(self.toolButtons or {}) do
        button.backgroundColor = tool == name and { 0.25, 0.5, 0.82 } or { 0.2, 0.22, 0.26 }
    end
end

function Content:handleActions()
    local map = self.fly.map
    if map:justPressed('editorToggleGrid') then
        self.grid:setVisible(not self.grid.visible)
    end
    if map:justPressed('editorFocus') then
        local items = self.selection:items()
        self:frame(#items > 0 and items or self.level.children)
    end
    if map:justPressed('editorFrameAll') then
        self:frame(self.level.children)
    end
    local selection, ops = self.selection, self.ops
    if map:justPressed('editorUndo') then
        self.undo:undo()
        self:refresh()
    elseif map:justPressed('editorRedo') then
        self.undo:redo()
        self:refresh()
    elseif map:justPressed('editorDelete') then
        ops:delete(selection:items())
    elseif map:justPressed('editorDuplicate') then
        ops:duplicate(selection:items())
    elseif map:justPressed('editorCopy') then
        self:notify(('Copied %d'):format(ops:copy(selection:items())))
    elseif map:justPressed('editorPaste') then
        ops:paste(self.level)
    elseif map:justPressed('editorSave') then
        self:saveLocation()
    elseif map:justPressed('editorOpen') then
        local latest = (self.recent or LocationIO.readRecent())[1]
        if latest then
            self:openLocation(latest)
        else
            self:notify('No recent files')
        end
    end
    -- Q/W/E/R pick tools only when they are not fly keys (the look button is up).
    if not self.fly:isLooking() then
        if map:justPressed('editorToolSelect') then
            self:setTool('Select')
        elseif map:justPressed('editorToolMove') then
            self:setTool('Move')
        elseif map:justPressed('editorToolRotate') then
            self:setTool('Rotate')
        elseif map:justPressed('editorToolScale') then
            self:setTool('Scale')
        elseif map:justPressed('editorToggleSpace') then
            self.space = self.space == 'World' and 'Local' or 'World'
            self:notify('Space: ' .. self.space)
        end
    end
end

-- Called after an undo or redo changed the world behind the panels' back.
function Content:refresh()
    self.treeVersion = self.treeVersion + 1
    local alive = {}
    for _, node in ipairs(self.selection:items()) do
        if not node.destroyed then
            alive[#alive + 1] = node
        end
    end
    if #alive ~= self.selection:count() then
        self.selection:set(alive)
    end
    for _, panel in pairs(self.panels or {}) do
        panel.dirty = true
    end
end

-- A message in the status bar for a few seconds (refused edits, hints).
function Content:notify(text)
    self.message, self.messageUntil = text, katsa.timer.getTime() + 4
end

function Content:update(dt)
    local scene = self.scene
    scene.world:updateNodes(dt)
    self.fly:update(dt)
    local position = scene.camera.position
    self.grid:follow(position[1], position[3])
    if self.viewportPressed then
        self.viewportPressed = false
        local x, y = katsa.mouse.getX(), katsa.mouse.getY()
        if not (self.tool ~= 'Select' and self.transform:begin(x, y)) then
            self:pick(x, y)
        end
    end
    self:handleActions()
    self:autosave(dt)
    self.transform:update()
    self.box:follow(self.selection:primary())
    for _, panel in pairs(self.panels or {}) do
        panel:update()
    end
    self:updateStatus()
end

function Content:updateStatus()
    local label = self.status
    if not label then
        return
    end
    local primary = self.selection:primary()
    local text = ('Tool %s (%s, %s pivot)   Snap %s   Grid %s %.2f   Fly speed %.1f   Selected %d%s'):format(
        self.tool,
        self.space,
        self.pivotMode:lower(),
        self.snap.enabled and 'on' or 'off',
        self.grid.visible and 'on' or 'off',
        self.grid.cell,
        self.fly.speed,
        self.selection:count(),
        primary and ('   [' .. tostring(primary.name) .. ']') or ''
    )
    if self.message and katsa.timer.getTime() < self.messageUntil then
        text = self.message
    end
    if text ~= label.text then
        label.text = text
    end
end

function Content:release()
    self.transform:release()
    self.grid:release()
    self.box:release()
    katsa.mouse.setRelativeMode(false)
end

Content.TOOLS = TOOLS

return Content
