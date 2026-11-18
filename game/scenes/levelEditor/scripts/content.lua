-- Level editor composition: world lighting, the Level root that owns every placed object, the
-- fly camera, grid, selection and the editor's per-frame commands. Controls are InputMap actions.
local Bounds = require('./core.bounds')
local EditorInput = require('./input.editorInput')
local FlyCamera = require('./view.flyCamera')
local Grid = require('./view.grid')
local Picking = require('source.engine.world.picking')
local Selection = require('./core.selection')
local SelectionBox = require('./view.selectionBox')
local Undo = require('./core.undo')

local Content = {}
Content.__index = Content

local TOOLS = { 'Select', 'Move', 'Rotate', 'Scale' }

function Content.new(scene)
    local settings = scene.settings.editor
    local world = scene.world
    local environment = world.environment
    environment.debug.gizmos.enabled = false
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
    self.tool, self.space = 'Select', 'World'
    self.grid = Grid.new(world, nil, settings.grid)
    self.box = SelectionBox.new(world)
    self:seed()

    local camera = scene.camera
    camera.near, camera.far, camera.fov = 0.05, 2000, settings.fov
    camera.drawDistance = 2000
    camera.position = { 9, 7, 9 }
    camera.rotation = { -25, -135, 0 }
    scene.input = EditorInput.new(scene, self)
    self.fly = FlyCamera.new(camera, scene.input.map, settings)
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
        end
    end
end

function Content:update(dt)
    local scene = self.scene
    scene.world:updateNodes(dt)
    self.fly:update(dt)
    local position = scene.camera.position
    self.grid:follow(position[1], position[3])
    if self.viewportPressed then
        self.viewportPressed = false
        self:pick(katsa.mouse.getX(), katsa.mouse.getY())
    end
    self:handleActions()
    self.box:follow(self.selection:primary())
    self:updateStatus()
end

function Content:updateStatus()
    local label = self.status
    if not label then
        return
    end
    local primary = self.selection:primary()
    local text = ('Tool %s (%s)   Grid %s %.2f   Fly speed %.1f   Selected %d%s'):format(
        self.tool,
        self.space,
        self.grid.visible and 'on' or 'off',
        self.grid.cell,
        self.fly.speed,
        self.selection:count(),
        primary and ('   [' .. tostring(primary.name) .. ']') or ''
    )
    if text ~= label.text then
        label.text = text
    end
end

function Content:release()
    self.grid:release()
    self.box:release()
    katsa.mouse.setRelativeMode(false)
end

Content.TOOLS = TOOLS

return Content
