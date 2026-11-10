-- NavLink3D: joins two places a NavMap3D cannot walk between and names the action that crosses
-- them ('jump', 'climb', 'door', 'teleport' or your own word). The link carries no cost: every
-- NavAgent3D prices actions itself (`actionCosts`), so one agent may jump gladly while another
-- never does. The plugin does not perform the action. An agent that routes through the link reports
-- it as its next action (`agent:getNextAction()`, `getActionTarget()`); your script moves the body
-- (a jump, a climb) and the agent carries on once the body stands at the far end. The scene needs
-- `plugins = { 'pathfinding' }` and a baked NavMap3D.
--
--   world:create('NavLink3D', { action = 'jump', position = { 0, 0, 0 }, endNode = landing })
local Definition = {
    base = 'Node3D',
    properties = {
        navMap = {
            default = nil,
            kind = 'node',
            nodeClass = 'NavMap3D',
            hint = 'NavMap3D to join. Empty = the first baked NavMap3D of the world.',
        },
        action = { default = 'jump', hint = 'Name of the action that crosses the link. Agents price it with actionCosts.' },
        endNode = {
            default = nil,
            kind = 'node',
            nodeClass = 'Node3D',
            hint = 'Node at the far end. Empty = the node position plus endOffset.',
        },
        endOffset = {
            default = { 0, 0, 4 },
            hint = 'Far end relative to this node (world axes), used when endNode is empty.',
        },
        bidirectional = { default = true, hint = 'Agents may cross both ways. Off: from this node to the far end only.' },
        active = { default = true, hint = 'Turn the link on and off (a door, a bridge). Routes are renewed.' },
        arcHeight = { default = 1, min = 0, hint = 'Height of the arc a jump script draws (the plugin only stores it).' },
        duration = { default = 0, min = 0, hint = 'Seconds the action should take for scripts that honour it (0 = their choice).' },
        state = { default = 'unlinked', readOnly = true, hint = 'linked once a NavMap3D has accepted the link.' },
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

local function endpoints(self)
    local start = self:getWorldPosition()
    local finish
    if self.endNode and not self.endNode.destroyed then
        finish = self.endNode:getWorldPosition()
    else
        local offset = self.endOffset
        finish = { start[1] + offset[1], start[2] + offset[2], start[3] + offset[3] }
    end
    return start, finish
end

local function signature(self, start, finish, map)
    return table.concat({
        start[1], start[2], start[3], finish[1], finish[2], finish[3], tostring(self.action),
        tostring(self.bidirectional), tostring(self.arcHeight), tostring(self.duration),
        tostring(map.mesh),
    }, ':')
end

function Definition:_remove()
    if self._link and self._map and not self._map.destroyed then
        self._map:removeLink(self._link)
    end
    self._link, self._map, self._signature, self.state = nil, nil, nil, 'unlinked'
end

-- The link the NavMap3D holds for this node, or nil.
function Definition:getLink()
    return self._link
end

function Definition:update()
    local map = mapOf(self)
    if not map then
        if self._link then
            self:_remove()
        end
        return
    end
    local start, finish = endpoints(self)
    local key = signature(self, start, finish, map)
    if key ~= self._signature then
        self:_remove()
        self._signature, self._map = key, map
        self._link = map:addLink({
            from = start,
            to = finish,
            action = self.action,
            bidirectional = self.bidirectional,
            arcHeight = self.arcHeight,
            duration = self.duration,
            data = self,
        })
        self.state = self._link and 'linked' or 'unlinked'
        if not self._connected then
            self._connected = true
            self:onDestroy(function()
                self:_remove()
            end)
        end
    end
    if self._link then
        map:setLinkEnabled(self._link, self.active)
    end
end

return Definition
