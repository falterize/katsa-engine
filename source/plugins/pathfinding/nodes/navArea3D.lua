-- NavArea3D: names a box-shaped region of a NavMap3D ('water', 'mud', 'road'). The area carries no
-- weight: every NavAgent3D decides what an area costs it with `areaCosts`, so one agent avoids
-- water while another wades through. The box is axis-aligned; it covers the walkable cells whose
-- surface lies inside it. Create it as a child of anything, in the same world as the NavMap3D.
--
--   world:create('NavArea3D', { area = 'water', size = { 10, 4, 6 }, position = { 0, 0, 0 } })
local Definition = {
    base = 'Node3D',
    properties = {
        navMap = {
            default = nil,
            kind = 'node',
            nodeClass = 'NavMap3D',
            hint = 'NavMap3D this area belongs to. Empty = every NavMap3D of the world.',
        },
        area = { default = 'water', hint = 'Name of the area. Agents price it with areaCosts; unset areas cost 1.' },
        size = { default = { 6, 4, 6 }, hint = 'Width, height and depth (X, Y, Z) of the box, centered on the node.' },
        active = { default = true, hint = 'Turn the area on and off without removing the node.' },
    },
}

local function worldOf(self)
    return self._world or self._sceneWorld
end

-- Tells every baked map to restamp its cells.
local function refresh(self)
    local world = worldOf(self)
    for _, map in ipairs(world and world.navMaps or {}) do
        if not map.destroyed and map:isBaked() and (self.navMap == nil or self.navMap == map) then
            map:applyAreas()
        end
    end
end

local function signature(self)
    local m = self:getWorldMatrix()
    local size = self.size
    return table.concat({
        m[4], m[8], m[12], size[1], size[2], size[3], tostring(self.area), tostring(self.active),
    }, ':')
end

function Definition:update()
    local world = worldOf(self)
    if not world then
        return
    end
    if not self._registered then
        self._registered = true
        world.navAreas = world.navAreas or {}
        world.navAreas[#world.navAreas + 1] = self
        self:onDestroy(function()
            for i, known in ipairs(world.navAreas) do
                if known == self then
                    table.remove(world.navAreas, i)
                    break
                end
            end
            refresh(self)
        end)
    end
    local key = signature(self)
    if key ~= self._signature then
        self._signature = key
        refresh(self)
    end
end

return Definition
