-- Level editor composition: world lighting, the Level root that owns every placed object, the
-- fly camera, grid, selection and the editor's per-frame commands. Controls are InputMap actions.
local Pointer = require('./input.pointer')
local Bounds = require('./core.bounds')
local EditorInput = require('./input.editorInput')
local FlyCamera = require('./view.flyCamera')
local EditorSettings = require('./io.editorSettings')
local NodeData = require('./core.nodeData')
local Focus = require('source.engine.ui.widgets.textFocus')
local Grid = require('./view.grid')
local LocationIO = require('./io.locationIO')
local Ops = require('./core.levelOps')
local Picking = require('source.engine.world.picking')
local Selection = require('./core.selection')
local Snap = require('./core.snap')
local Menus = require('./ui.support.menus')
local LightViz = require('./view.lightViz')
local SelectionBox = require('./view.selectionBox')
local TransformTool = require('./tools.transformTool')
local Undo = require('./core.undo')

local Content = {}
Content.__index = Content

local TOOLS = { 'Select', 'Move', 'Rotate', 'Scale' }

function Content.new(scene)
    local settings = scene.settings.editor
    local prefs = EditorSettings.parse(katsa.filesystem.read(EditorSettings.FILE))
    -- The 3D view is a ViewportFrame with its own World3D and camera, so it can be sized and
    -- placed between the docks. The scene's main World3D stays empty and only carries the UI.
    local ui = scene.root:find('World3D/World2D')
    local viewport = ui:create('ViewportFrame', {
        name = 'Viewport',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        zIndex = 1,
    }, ui.content)
    local root3D = ui:create('World3D', { name = 'EditorWorld', timeScale = 0 }, viewport)
    local world = root3D._world
    local environment = world.environment
    environment.debug.gizmos.enabled = false -- the editor draws its own light visualisation (view/lightViz)
    environment.shadows.enabled = true
    environment.ambient = { 130, 136, 150 }
    environment.sky.enabled = true
    world:create('DirectionalLight3D', {
        name = 'EditorSun',
        rotation = { 50, 35, 0 },
        color = { 255, 244, 222 },
        brightness = 1.1,
    })

    local self = setmetatable({
        scene = scene,
        settings = settings,
        prefs = prefs,
        ui = ui,
        viewport = viewport,
        root3D = root3D,
        world = world,
    }, Content)
    self.level = world:create('Node3D', { name = 'Level' })
    self.selection = Selection.new()
    self.undo = Undo.new()
    self.treeVersion = 0
    self.tool, self.space, self.pivotMode = 'Select', 'World', 'Center'
    self.snap = {
        enabled = prefs.snap.enabled,
        move = prefs.snap.move,
        rotate = prefs.snap.rotate,
        scale = prefs.snap.scale,
        surface = false,
    }
    self.grid = Grid.new(world, nil, {
        cell = prefs.grid.cell,
        visible = prefs.grid.visible,
        major = prefs.grid.major,
        count = prefs.grid.count,
    })
    self.lightViz = LightViz.new(world, self.level)
    self.boxes = {} -- outline pool: [1] is the primary selection, the rest are the others
    self.ops = Ops.new(self)
    self:seed()
    self.ops:adopt(self.level)
    self.recent = LocationIO.readRecent()
    self.savedVersion = 0

    local camera = root3D:create('Camera3D', { name = 'EditorCamera' })
    root3D.currentCamera = camera
    self.camera = camera
    camera.near, camera.far, camera.fov = 0.05, 2000, prefs.camera.fov
    camera.drawDistance = 2000
    camera.position = { 9, 7, 9 }
    camera.rotation = { -25, -135, 0 }
    scene.input = EditorInput.new(scene, self)
    if next(prefs.bindings) then
        pcall(scene.input.map.loadData, scene.input.map, prefs.bindings)
    end
    local fly = {}
    for key, value in pairs(settings) do
        fly[key] = value
    end
    fly.flySpeed, fly.sensitivity = prefs.camera.flySpeed, prefs.camera.sensitivity
    self.fly = FlyCamera.new(camera, scene.input.map, fly)
    self.transform = TransformTool.new(self)
    return self
end

-- A few starter objects so a fresh editor is not an empty void.
function Content:seed()
    local world = self.world
    local function mesh(name, kind, position, size, color)
        return world:create('Mesh3D', {
            name = name,
            kind = kind,
            position = position,
            size = size,
            color = color,
            maxDistance = 0,
        }, self.level)
    end
    mesh('Floor', 'cube', { 0, -0.25, 0 }, { 20, 0.5, 20 }, { 0.55, 0.58, 0.62, 1 })
    mesh('Box', 'cube', { -3, 1, 2 }, { 2, 2, 2 }, { 0.85, 0.35, 0.3, 1 })
    mesh('Ball', 'sphere', { 2.5, 1, -1 }, { 2, 2, 2 }, { 0.3, 0.6, 0.9, 1 })
    -- Coloured point lights so lighting and shadows are visible from the first frame.
    for _, light in ipairs({
        { 'Red Light', { -6, 3, -3 }, { 255, 70, 60 } },
        { 'Green Light', { 1, 3.5, -5 }, { 70, 255, 110 } },
        { 'Blue Light', { 6, 3, 3 }, { 70, 130, 255 } },
    }) do
        world:create('PointLight3D', {
            name = light[1],
            position = light[2],
            color = light[3],
            brightness = 2,
            range = 14,
            radius = 1.2,
        }, self.level)
    end
end

-- The direct child of Level that contains a picked mesh (a group when it is inside one).
-- A point in front of the camera for new objects: where the view centre meets the ground, or
-- eight units ahead; snapped to the move step when snapping is on.
-- Where a new object goes: under the viewport point (vx, vy) when given, else the view centre.
function Content:placement(vx, vy)
    local ray = self.transform:ray(vx or (self.viewport._canvasWidth or 1280) / 2, vy or (self.viewport._canvasHeight or 720) / 2)
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

-- Writes the editor preferences (theme, dock sizes, snap, grid, camera, rebound keys).
function Content:savePrefs()
    local prefs = self.prefs
    prefs.snap.enabled, prefs.snap.move = self.snap.enabled, self.snap.move
    prefs.snap.rotate, prefs.snap.scale = self.snap.rotate, self.snap.scale
    prefs.grid.cell, prefs.grid.visible = self.grid.cell, self.grid.visible
    prefs.grid.major, prefs.grid.count = self.grid.settings.major, self.grid.settings.count
    prefs.camera.flySpeed = self.fly.speed
    prefs.camera.sensitivity = self.fly.sensitivity
    prefs.camera.fov = self.camera.fov
    if self.dock then
        prefs.layout = self.dock:sizes()
    end
    local bindings = {}
    for name, entry in pairs(self.scene.input.map:toData()) do
        if name:sub(1, 6) == 'editor' then
            bindings[name] = entry
        end
    end
    prefs.bindings = bindings
    LocationIO.write(EditorSettings.FILE, EditorSettings.serialize(prefs))
end

-- Selection by rectangle (viewport pixels): a top-level object is taken when its centre projects
-- inside; Ctrl adds to the current selection.
function Content:boxSelect(x0, y0, x1, y1)
    local left, right = math.min(x0, x1), math.max(x0, x1)
    local top, bottom = math.min(y0, y1), math.max(y0, y1)
    local picked = {}
    for _, node in ipairs(self.level.children) do
        if not node.destroyed and node.visible ~= false and not self.ops:isLocked(node) then
            local center = Bounds.sphere({ node })
            if center then
                local x, y, depth = self.camera:project(center)
                if depth and x >= left and x <= right and y >= top and y <= bottom then
                    picked[#picked + 1] = node
                end
            end
        end
    end
    if self.fly.map:isDown('editorAdd') then
        for _, node in ipairs(self.selection:items()) do
            picked[#picked + 1] = node
        end
    end
    self.selection:set(picked)
end

-- A press in the viewport either grabs a gizmo handle or starts a click / rectangle selection;
-- the click is resolved on release so a drag can become a box.
function Content:updateSelectionDrag()
    local map = self.fly.map
    if self.viewportPressed then
        self.viewportPressed = false
        local mx, my = Pointer.getX(), Pointer.getY()
        local x, y = self:viewportPoint(mx, my)
        if x then
            if not (self.tool ~= 'Select' and self.transform:begin(x, y)) then
                self.marquee = { x = x, y = y, mx = mx, my = my, active = false }
            end
        end
    end
    local marquee = self.marquee
    if not marquee then
        return
    end
    local mx, my = Pointer.getX(), Pointer.getY()
    local frame, ui = self.marqueeFrame, self.ui
    if map:isDown('editorPick') then
        if not marquee.active and math.abs(mx - marquee.mx) + math.abs(my - marquee.my) > 6 then
            marquee.active = true
        end
        if marquee.active and frame then
            local ax, ay = (marquee.mx - ui.offsetX) / ui.scale, (marquee.my - ui.offsetY) / ui.scale
            local bx, by = (mx - ui.offsetX) / ui.scale, (my - ui.offsetY) / ui.scale
            frame.position = { 0, math.min(ax, bx), 0, math.min(ay, by) }
            frame.size = { 0, math.abs(bx - ax), 0, math.abs(by - ay) }
            frame.visible = true
        end
    else
        self.marquee = nil
        if frame then
            frame.visible = false
        end
        if marquee.active then
            local x, y = self:viewportPoint(mx, my, true)
            if x then
                self:boxSelect(marquee.x, marquee.y, x, y)
            end
        else
            self:pick(marquee.x, marquee.y)
        end
    end
end

function Content:selectAll()
    local all = {}
    for _, node in ipairs(self.level.children) do
        if not self.ops:isLocked(node) then
            all[#all + 1] = node
        end
    end
    self.selection:set(all)
end

local function destroyLevelChildren(self)
    for index = #self.level.children, 1, -1 do
        local node = self.level.children[index]
        self.ops:forget(node)
        node:destroy()
    end
end

function Content:newLocation()
    self:clearLevel()
    self.fileName, self.savedVersion = nil, self.undo.version
    self:notify('New empty location')
end

-- Writes a package to editor/exports/<name>.katsa (the same format as Save, a separate folder).
function Content:exportLocation(name)
    local safe = LocationIO.pathFor(name):match('([^/]+)$')
    local path = LocationIO.EXPORTS .. '/' .. safe
    local ok, bytes, warnings = pcall(LocationIO.export, self)
    if not ok then
        self:notify('Export failed: ' .. tostring(bytes))
        return false
    end
    local written, message = LocationIO.write(path, bytes)
    if not written then
        self:notify('Export failed: ' .. tostring(message))
        return false
    end
    self:notify(('Exported %s/%s%s'):format(katsa.filesystem.getSaveDirectory(), path, #warnings > 0 and ('  (' .. warnings[1] .. ')') or ''))
    return true
end

-- Adds the objects of a .katsa file to the current level (one undo step).
function Content:importLocation(path)
    local bytes = katsa.filesystem.read(path)
    if not bytes then
        self:notify('Cannot read ' .. path)
        return false
    end
    local count, message = LocationIO.import(self, bytes, true)
    if not count then
        self:notify(tostring(message))
        return false
    end
    self:notify(('Imported %d objects from %s'):format(count, path))
    return true
end

-- Removes every object from the Level (used before a file is opened or a new one started).
function Content:clearLevel()
    self.selection:clear()
    destroyLevelChildren(self)
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
    if self.panels and self.panels.browser then
        self.panels.browser.dirty = true
    end
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

-- True when the pointer is over a panel; the viewport itself does not count as UI.
function Content:overUI()
    local node = self.ui:hit(Pointer.getX(), Pointer.getY())
    if not node then
        return false
    end
    while node do
        if node == self.viewport then
            return false
        end
        node = node.parent
    end
    return true
end

-- Window pixels to the viewport's own pixels (what the camera and Picking use); nil when the
-- pointer is outside the viewport (unless `free`, used while dragging) or it has not been drawn yet.
function Content:viewportPoint(x, y, free)
    local viewport, ui = self.viewport, self.ui
    local canvasWidth, canvasHeight = viewport._canvasWidth, viewport._canvasHeight
    if not canvasWidth then
        return nil
    end
    local lx = ((x - ui.offsetX) / ui.scale - viewport._x) * canvasWidth / math.max(1, viewport._width)
    local ly = ((y - ui.offsetY) / ui.scale - viewport._y) * canvasHeight / math.max(1, viewport._height)
    if not free and (lx < 0 or ly < 0 or lx > canvasWidth or ly > canvasHeight) then
        return nil
    end
    return lx, ly
end

function Content:levelChild(object)
    local node = object
    while node and node.parent ~= self.level do
        node = node.parent
    end
    return node
end

function Content:pick(x, y)
    local map = self.fly.map
    local hit = Picking.raycast(self.world, self.camera, x, y)
    local node = self.lightViz:ownerOf(hit) or (hit and self:levelChild(hit))
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

-- Opens a pop-up list at window pixel (x, y) in UI units; `point` (viewport pixels) is where
-- objects created from it are placed.
function Content:popup(items, x, y, opts)
    self.panels.popup:show(items, x, y, opts)
end

function Content:openCreate(x, y, point)
    self:popup(Menus.createItems(self, point), x, y, { width = 260, search = true })
end

-- Pointer position in UI units.
function Content:pointer()
    local ui = self.ui
    return (Pointer.getX() - ui.offsetX) / ui.scale, (Pointer.getY() - ui.offsetY) / ui.scale
end

-- Right-click without dragging in the viewport: a menu for the object under it, or for the
-- empty space. A held right button that moves is the fly-look and never opens a menu.
function Content:viewportMenu(tap)
    local vx, vy = self:viewportPoint(tap.x, tap.y)
    if not vx then
        return
    end
    local hit = Picking.raycast(self.world, self.camera, vx, vy)
    local node = self.lightViz:ownerOf(hit) or (hit and self:levelChild(hit))
    if node and self.ops:isLocked(node) then
        node = nil
    end
    local ui = self.ui
    local ux, uy = (tap.x - ui.offsetX) / ui.scale, (tap.y - ui.offsetY) / ui.scale
    local point = { vx, vy }
    if node then
        if not self.selection:has(node) then
            self.selection:set({ node })
        end
        self:popup(Menus.node(self), ux, uy, { width = 220 })
    else
        self:popup(Menus.empty(self, point), ux, uy, { width = 240 })
    end
end

function Content:frame(nodes)
    local center, radius = Bounds.sphere(nodes)
    if center then
        self.fly:frame(center, radius)
    end
end

function Content:setTool(name)
    self.tool = name -- the toolbar shows the active tool from this field every frame
end

function Content:handleActions()
    local map = self.fly.map
    if map:justPressed('editorCreate') then
        local x, y = self:pointer()
        local vx, vy = self:viewportPoint(Pointer.getX(), Pointer.getY())
        self:openCreate(x, y, vx and { vx, vy } or nil)
    end
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
    elseif map:justPressed('editorSelectAll') then
        self:selectAll()
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
    self.fly:update(dt)
    local position = self.camera.position
    self.grid:follow(position[1], position[3])
    self:updateSelectionDrag()
    local tap = self.rmbTap
    if tap then
        self.rmbTap = nil
        self:viewportMenu(tap)
    end
    if not Focus.current then -- typing in a field must not trigger editor shortcuts
        self:handleActions()
    end
    self:autosave(dt)
    self.lightViz:update(self.selection, true, self.camera)
    self.transform:update()
    self:followOutlines(self.selection:items())
    for _, panel in pairs(self.panels or {}) do
        panel:update()
    end
    if self.dock then
        self.dock:update()
    end
    self:updateStatus()
end

-- One outline per selected node. The primary (the gizmo's node) is orange, the others are
-- a paler yellow; unused pool entries are hidden.
function Content:followOutlines(items)
    local boxes, primary = self.boxes, self.selection:primary()
    local used = 0
    for _, node in ipairs(items) do
        if not LightViz.isLight(node) then -- lights are shown by the light visualisation
            used = used + 1
            local box = boxes[used]
            if not box then
                box = SelectionBox.new(self.world, nil, used)
                boxes[used] = box
            end
            box:setPrimary(node == primary)
            box:follow(node)
        end
    end
    for index = used + 1, #boxes do
        boxes[index]:follow(nil)
    end
end

function Content:updateStatus()
    local label = self.status
    if not label then
        return
    end
    local primary = self.selection:primary()
    local text = self.hint or ('Tool %s (%s, %s pivot)   Snap %s   Grid %s %.2f   Fly speed %.1f   Selected %d%s'):format(
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
    if katsa.dropHandler == self.dropHandler then
        katsa.dropHandler = nil
    end
    self.transform:release()
    self.grid:release()
    self.lightViz:release()
    for _, box in ipairs(self.boxes) do
        box:release()
    end
    Pointer.reset()
    katsa.mouse.setRelativeMode(false)
end

Content.TOOLS = TOOLS

return Content
