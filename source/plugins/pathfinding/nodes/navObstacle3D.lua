-- NavObstacle3D: blocks a circle or box on the NavMesh of a NavMap3D while it exists and is enabled.
-- Routes and crowd agents go around it; the map rebuilds only the tiles it touches. Moving the
-- node (a door, a crate, a parked car) moves the obstacle. The scene needs `plugins = { 'pathfinding' }`
-- and a baked NavMap3D.
--
--   world:create('NavObstacle3D', { shape = 'Circle', radius = 2, position = { 10, 0, 4 } })
local Definition = {
    base = 'Node3D',
    properties = {
        navMap = {
            default = nil,
            kind = 'node',
            nodeClass = 'NavMap3D',
            hint = 'NavMap3D to block. Empty = the first baked NavMap3D of the world.',
        },
        shape = { default = 'Circle', options = { 'Circle', 'Box' }, hint = 'Footprint on the ground.' },
        radius = { default = 1, min = 0.05, hint = 'Radius of the circle.', visibleWhen = { key = 'shape', equals = 'Circle' } },
        size = { default = { 2, 2 }, hint = 'Width and depth (X, Z) of the box; it turns with the node around Y.', visibleWhen = { key = 'shape', equals = 'Box' } },
        height = { default = 0, min = 0, hint = 'Only block floors whose surface is within this height of the node (0 = every floor).' },
        blocking = { default = true, hint = 'Turn the obstacle on and off without removing the node.' },
    },
}

local function mapOf(self)
    local map = self.navMap
    if map then
        return not map.destroyed and map:isBaked() and map or nil
    end
    local world = self._world or self._sceneWorld
    for _, known in ipairs(world and world.navMaps or {}) do
        if not known.destroyed and known:isBaked() then
            return known
        end
    end
end

local function shapeOf(self)
    local matrix = self:getWorldMatrix()
    local shape = { x = matrix[4], z = matrix[12] }
    if self.shape == 'Box' then
        shape.kind = 'box'
        shape.halfX, shape.halfZ = self.size[1] / 2, self.size[2] / 2
        shape.angle = math.deg(math.atan2(-matrix[3], matrix[1]))
    else
        shape.kind, shape.radius = 'circle', self.radius
    end
    if self.height > 0 then
        shape.y, shape.height = matrix[8], self.height
    end
    return shape
end

-- The part of the footprint that, when changed, needs the obstacle to be covered again.
local function signature(shape)
    return table.concat({
        shape.kind,
        shape.x,
        shape.z,
        shape.radius or 0,
        shape.halfX or 0,
        shape.halfZ or 0,
        shape.angle or 0,
        shape.y or 0,
        shape.height or 0,
    }, ':')
end

function Definition:_remove()
    if self._handle and self._map and not self._map.destroyed then
        self._map:removeObstacle(self._handle)
    end
    self._handle, self._map, self._signature = nil, nil, nil
end

function Definition:update()
    local map = mapOf(self)
    if not map or not self.blocking then
        if self._handle then
            self:_remove()
        end
        return
    end
    if self._map ~= map then
        self:_remove()
    end
    local shape = shapeOf(self)
    local key = signature(shape)
    if key == self._signature then
        return
    end
    if self._handle then
        map:removeObstacle(self._handle)
    end
    self._handle, self._map, self._signature = map:addObstacle(shape), map, key
    if not self._connected then
        self._connected = true
        self:onDestroy(function()
            self:_remove()
        end)
    end
end

return Definition
