local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local Node = require('../nodes')
require('./nodes')

local UI = Node.getClass('World2D')
UI.__index = UI

function UI.new(width, height, resources)
    assert(
        width > 0 and height > 0 and resources,
        'UI requires positive dimensions and a resource scope'
    )
    local self = setmetatable({
        width = width,
        height = height,
        resources = resources,
        children = {},
        fonts = {},
        scale = 1,
        offsetX = 0,
        offsetY = 0,
        density = 1,
        layoutMode = 'Viewport',
        time = 0,
        revision = 0,
        animated = false,
    }, UI)
    self._stencilRectangle = function()
        local n = self._stencilNode
        katsa.graphics.rectangle('fill', n._x, n._y, n._width, n._height, n._radius)
    end
    self._clearStencil = function() end
    Node.adopt(self, 'World2D')
    Node.create('Environment', {}, self, self)
    self.content = self:canvasGroup({ name = 'HUD', size = { 1, 0, 1, 0 } })
    return self
end

function UI.newBillboard(world, settings)
    return require('./spatial.billboard').new(world, settings)
end

function UI:invalidate()
    self.revision = self.revision + 1
end

function UI:invalidatePaint()
    local arranged = self._layoutRevision == self.revision
    self.revision = self.revision + 1
    if arranged then
        self._layoutRevision = self.revision
    end
end

function UI:layerVisible(node)
    local Layers = require('../world.visibilityLayers')
    local world = self._sceneWorld or self.owner and (self.owner._world or self.owner._sceneWorld)
    return Layers.visible(world, node, Layers.viewer(self, node))
end

function UI:validateParent(node, parent)
    assert(
        parent and parent._node and not parent.destroyed,
        'UI nodes require an explicit live parent'
    )
    local class = node._registeredClass
        or node._class
        or Node.getClass(node.className or 'Frame', self)
    if class.modifier then
        assert(
            parent:isA('UINode')
                and (
                    not parent.modifier
                    or node.className == 'UIGradient' and parent:isA('UIStroke')
                ),
            'UI modifiers require a visual UI element parent'
        )
    end
    local spatial = parent
    while spatial and not spatial:isA('Node2D') and not spatial:isA('World2D') do
        spatial = spatial.parent
    end
    if spatial and spatial:isA('Node2D') then
        assert(spatial._plane == self, 'Spatial widgets must retain their World2D owner')
        return
    end
    if node.className == 'CanvasGroup' then
        assert(
            parent == self
                or parent == self.owner
                or (
                    parent.ui == self
                    and parent:isA('UINode')
                    and (
                        not parent.modifier
                        or node.className == 'UIGradient' and parent:isA('UIStroke')
                    )
                ),
            'CanvasGroup requires its ScreenUI owner or another CanvasGroup'
        )
    else
        local root = parent
        while
            root
            and not root:isA('CanvasGroup')
            and not (root:isA('BillboardUI') or root:isA('SurfaceUI'))
        do
            root = root.parent
        end
        assert(
            root and (root == self.owner or root.ui == self),
            'UI widgets require a CanvasGroup or BillboardUI ancestor from their UI owner'
        )
    end
end

function UI:add(node, parent)
    self:validateParent(node, parent)
    self.order = (self.order or 0) + 1
    node._order = self.order
    node.zIndex = node.zIndex or 0
    Node.adopt(node, node.className or 'Frame')
    assert(node:isA('UINode'), 'UI:add requires a UINode instance')
    node.children = node.children or {}
    node.visible, node.enabled = node.visible ~= false, node.enabled ~= false
    require('./layout.metrics').resolve(
        node.size,
        0,
        0,
        node.sizeRelativeTo or node.relativeTo
    )
    node.ui = self
    node.parent = parent
    if node:isA('UICorner') or node:isA('UIStroke') then
        self.hasCorners = true
    end
    if node.material and node.material.animated then
        self.animated = true
    end
    self:invalidate()
    return node
end

function UI:canvasGroup(settings, parent)
    return self:create('CanvasGroup', settings, parent or self)
end

function UI:bindBillboard(owner)
    assert(
        owner:isA('BillboardUI') or owner:isA('SurfaceUI'),
        'UI owner must be a BillboardUI or SurfaceUI'
    )
    self.content:destroy()
    -- World-space UI retains a flattened visual hierarchy for compatibility.
    -- Its required Environment belongs to the host while the World2D owns its settings.
    self.environment._environmentOwner = owner
    self.environment.parent = owner
    self.owner, self.content, self.children = owner, owner, owner.children
end

function UI:container(settings, parent)
    return self:create('Frame', settings, parent)
end

function UI:text(settings, parent)
    return self:create('TextLabel', settings, parent)
end

function UI:image(settings, parent)
    return self:create('ImageLabel', settings, parent)
end

function UI:button(settings, parent)
    return self:create('Button', settings, parent)
end

function UI:slider(settings, parent)
    return self:create('Slider', settings, parent)
end

function UI:scroll(settings, parent)
    return self:create('ScrollFrame', settings, parent)
end

function UI:set(node, values)
    for key, value in pairs(values) do
        node[key] = value
    end
    self:invalidate()
    return node
end

function UI:remove(node)
    node:destroy()
    self:invalidate()
end

function UI.udim2(scaleX, offsetX, scaleY, offsetY)
    return require('../math.udim2').new(scaleX, offsetX, scaleY, offsetY)
end

function UI:bindWorld(world)
    assert(not self._sceneWorld or self._sceneWorld == world, 'UI cannot move between scene scopes')
    world.uis = world.uis or {}
    local found = false
    for _, ui in ipairs(world.uis) do
        if ui == self then
            found = true
        end
    end
    if not found then
        world.uis[#world.uis + 1] = self
        self:onDestroy(function()
            for i, ui in ipairs(world.uis) do
                if ui == self then
                    table.remove(world.uis, i)
                    break
                end
            end
        end)
    end
    if not self.owner then
        self.parent = world.root
    end
    self.nodeTypes = world.nodeTypes or {}
    world.nodeTypes = self.nodeTypes
    require('../nodes.core.hierarchy').bind(self, world.nodeTree, world)
    return self
end

function UI:create(className, properties, parent)
    properties = properties or {}
    local class = Node.getClass(className, self)
    if class._types.Node2D or class._types.Constraint2D then
        parent = parent or self
    end
    local node = Node.create(className, properties, parent, self)
    if node._class.registrationWorld and node._class.scriptUpdate then
        node:setProcess(true)
    end
    return node
end

function UI:setCurrentCamera(camera)
    assert(
        camera == nil or camera:isA('Camera2D') and camera._plane == self and not camera.destroyed,
        'Camera2D must belong to this World2D'
    )
    rawset(self, '_currentCamera', camera)
    return camera
end

UI.setCamera2D = UI.setCurrentCamera

function UI:screenToWorld2D(x, y)
    x, y = (x - self.offsetX) / self.scale, (y - self.offsetY) / self.scale
    if self.currentCamera then
        return self.currentCamera:screenToWorld(x, y, self.width, self.height)
    end
    return x, self.height - y
end

function UI:worldToScreen2D(x, y)
    if self.currentCamera then
        x, y = self.currentCamera:worldToScreen(x, y, self.width, self.height)
    else
        y = self.height - y
    end
    return x * self.scale + self.offsetX, y * self.scale + self.offsetY
end

function UI:createPhysics(options)
    assert(not self.owner, 'Physical World2D must be a screen world')
    assert(not self.physics2D, 'World2D physics is already configured')
    options = options or {}
    if options.debug ~= nil then
        self.environment.debug.physics.enabled = options.debug == true
    end
    options.debugSettings = self.environment.debug.physics
    self.physics2D = require('../physics.2d').new(options)
    self.physics2D.resources = self.resources
    require('../world.gravity').bind(self, self.physics2D)
    self:onDestroy(function()
        self.physics2D:release()
    end)
    return self.physics2D
end

function UI:font(size)
    size = size or 22
    local density = self.density
    local key = size .. ':' .. density
    if not self.fonts[key] then
        local font = self.resources:own(katsa.graphics.newFont(size, 'normal', density))
        font:setFilter('linear', 'linear')
        self.fonts[key] = font
    end
    return self.fonts[key]
end

function UI:rasterFont(size)
    local density = self.density
    local pixels = math.max(1, math.floor((size or 22) * density + 0.5))
    local key = 'pixels:' .. pixels
    local font = self.fonts[key]
    if not font then
        -- Keep glyph advances and atlas quads in physical pixels. LÃƒâ€“VE 11.x
        -- rounds fractional-DPI metrics in logical units before drawing them.
        font = self.resources:own(katsa.graphics.newFont(pixels, 'normal', 1))
        font:setFilter('linear', 'linear')
        self.fonts[key] = font
    end
    return font, 1 / density
end

function UI.isWorking(node)
    while node do
        if
            node.enabled == false
            or node.ui and node.layerGroup and not node.ui:layerVisible(node)
        then
            return false
        end
        node = node.parent
    end
    return true
end

function UI.canInteract(node)
    while node do
        if
            node.destroyed
            or node:isA('UINode') and node.ui and not node.ui:layerVisible(node)
            or node.visible == false
            or node.enabled == false
            or node.interactable == false
            or (node:isA('CanvasGroup') or node:isA('World2D') or node:isA('Node2D'))
                and (node.transparency or 0) >= 1
        then
            return false
        end
        node = node.parent
    end
    return true
end

function UI:updatePhysics(dt)
    self._simulationDelta = require('../world.clock').delta(self, dt)
    if self.physics2D then
        self.physics2D:update(self._simulationDelta)
    end
    -- Match World3D: sample emitter poses after native bodies have advanced.
    if self.particles then
        self.particles:update(self._simulationDelta)
    end
end

function UI:update(realDt, simulationDt)
    local sceneDt = simulationDt == nil and realDt or simulationDt
    self._simulationDelta = require('../world.clock').delta(self, sceneDt)
    self.time = self.time + require('../world.clock').delta(self, realDt)
    if (self.physics2D or self.particles) and self.autoUpdatePhysics ~= false then
        self:updatePhysics(sceneDt)
    end
    if self.currentCamera then
        self.currentCamera:updateFollow()
    end
    -- Each nested viewport owns a World3D clock; the enclosing UI clock must not
    -- multiply it. Only the application's common simulation delta crosses worlds.
    require('./spatial.viewportUpdate').update(self.children, sceneDt)
end

function UI:release()
    if self.physics2D then
        self.physics2D:release()
    end
    local destroying = self._destroying
    self._destroying = true
    while #self.children > 0 do
        self.children[#self.children]:destroy()
    end
    self._destroying = destroying
    self.fonts = {}
    self:invalidate()
    -- Fonts and canvases belong to the explicit resource scope, released by its owner.
end
require('./layout.arrangement').install(UI)
require('./drawing.drawing').install(UI)
require('./input.interaction').install(UI)
require('./layout.changeTracking').install(UI)
return UI
