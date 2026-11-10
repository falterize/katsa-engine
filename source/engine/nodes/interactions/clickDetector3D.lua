local Node = require('../core.baseNode')
local M = require('../../math.math3d')

local Class = Node.define('ClickDetector3D', 'Node')

require('../../components.ordering.priority').describe(Class)

function Class.initialize(self)
    self.radius = self.radius or 32
    require('source.engine.components.ordering.priority').normalize(self)
    self.enabled = self.enabled ~= false
    self._requestedAdornee = rawget(self, 'adornee')
    rawset(self, 'adornee', nil)
end

function Class.mount(world, properties, parent)
    local node = Node.new('ClickDetector3D', properties, parent)
    node._world = world
    require('source.engine.world.surfaces.support').initialize(node, node._requestedAdornee)
    node._requestedAdornee = nil
    world.clickDetectors = world.clickDetectors or {}
    world._clickDetectorCount = (world._clickDetectorCount or 0) + 1
    node._order = world._clickDetectorCount -- creation order: detectors fire in it
    world.clickDetectors[node] = true
    node:onDestroy(function()
        world.clickDetectors[node] = nil
    end)
    return node
end

function Class:setAdornee(node)
    assert(node == nil or node:isA('Node3D'), 'ClickDetector3D Adornee must be a Node3D')
    return require('source.engine.world.surfaces.support').set(self, node)
end

function Class:getTarget()
    if self._adorneeLost then
        return
    end
    return self.adornee or self.parent
end

function Class:canActivate()
    if not self.enabled or self.destroyed or self._destroying then
        return false
    end
    assert(
        type(self.radius) == 'number' and self.radius >= 0 and self.radius < math.huge,
        'ClickDetector3D Radius must be finite and nonnegative'
    )
    local object = self:getTarget()
    if
        not object
        or not object:isA('Node3D')
        or object.visible == false
        or object.isVisible and not object:isVisible()
    then
        return false
    end
    local world = self._sceneWorld or object._world
    local source = self.positionSource or world.interactionSource
    if
        not source
        or source.destroyed
        or not source.getWorldPosition
        or (source._world or source._sceneWorld) ~= world
    then
        return false
    end
    -- Distance targets the Mesh3D spatial origin, not its rendered bounding-box edge.
    return M.distanceSquared(source:getWorldPosition(), object:getWorldPosition())
        <= self.radius ^ 2
end

-- True when `mesh` is the target or lies anywhere below it, so one detector on a Node3D covers a
-- whole model of many parts.
function Class:contains(mesh)
    local target = self:getTarget()
    while mesh do
        if mesh == target then
            return true
        end
        mesh = mesh.parent
    end
    return false
end

local function alive(self)
    return self.enabled and not self.destroyed and not self._destroying
end

-- Pointer verbs, the same three as on UI nodes. A pointer `id` ('mouse', a touch id, or 'code')
-- presses, then either releases (a `click` follows) or is cancelled (it left the object or turned
-- into a camera drag). Signals: press, release, click, cancel; each gets (pointerId, target).
-- `checked` = true also requires the activation rules (radius, visibility, an interaction
-- source), like a player's click; calls from code skip them by default.
function Class:press(id, checked)
    id = id or 'code'
    if not alive(self) or checked and not self:canActivate() then
        return false
    end
    self._held = self._held or {}
    self._held[id] = true
    self:emit('press', id, self:getTarget())
    return true
end

function Class:release(id)
    id = id or 'code'
    if not (self._held and self._held[id]) then
        return false
    end
    self._held[id] = nil
    self:emit('release', id, self:getTarget())
    self:emit('click', id, self:getTarget())
    return true
end

function Class:cancel(id)
    id = id or 'code'
    if not (self._held and self._held[id]) then
        return false
    end
    self._held[id] = nil
    self:emit('cancel', id, self:getTarget())
    return true
end

-- Press and release in one go: emits press, release and click.
function Class:click(id, checked)
    return self:press(id, checked) and self:release(id)
end

return Class
