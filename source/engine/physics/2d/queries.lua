local Queries = {}

local function accepts(fixture, filter)
    local data = fixture:getUserData()
    if
        not data
        or data.body.destroyed
        or data.body._pendingDestroy
        or data.body.object.canQuery == false
    then
        return false
    end
    return not filter or filter(data.body, data.collider)
end

function Queries.raycast(self, a, b, filter, out)
    assert(not self.released and not self._querying, 'Invalid or reentrant Physics2D query')
    assert(a[1] ~= b[1] or a[2] ~= b[2], 'Ray endpoints must differ')
    local f, hit = self.factor, nil
    self._querying = true
    local ok, message = pcall(
        self.world.rayCast,
        self.world,
        a[1] * f,
        a[2] * f,
        b[1] * f,
        b[2] * f,
        function(fixture, x, y, nx, ny, fraction)
            if not accepts(fixture, filter) then
                return -1
            end
            local data = fixture:getUserData()
            hit = out or hit or {}
            hit.body, hit.collider, hit.fraction = data.body, data.collider, fraction
            hit.position, hit.normal = hit.position or {}, hit.normal or {}
            hit.position[1], hit.position[2] = x / f, y / f
            hit.normal[1], hit.normal[2] = nx, ny
            return fraction
        end
    )
    self._querying = false
    self:flush()
    if not ok then
        error(message, 0)
    end
    return hit
end

function Queries.raycastAll(self, a, b, filter)
    local hits = {}
    -- The nearest-hit API clips traversal; collect-all must leave the ray unclipped.
    assert(not self.released and not self._querying, 'Invalid or reentrant Physics2D query')
    assert(a[1] ~= b[1] or a[2] ~= b[2], 'Ray endpoints must differ')
    local f = self.factor
    self._querying = true
    local ok, message = pcall(
        self.world.rayCast,
        self.world,
        a[1] * f,
        a[2] * f,
        b[1] * f,
        b[2] * f,
        function(fixture, x, y, nx, ny, fraction)
            if accepts(fixture, filter) then
                local data = fixture:getUserData()
                hits[#hits + 1] = {
                    body = data.body,
                    collider = data.collider,
                    fraction = fraction,
                    position = { x / f, y / f },
                    normal = { nx, ny },
                }
            end
            return 1
        end
    )
    self._querying = false
    self:flush()
    if not ok then
        error(message, 0)
    end
    table.sort(hits, function(aHit, bHit)
        return aHit.fraction < bHit.fraction
    end)
    return hits
end

local function overlap(self, x1, y1, x2, y2, filter, test, out)
    assert(not self.released and not self._querying, 'Invalid or reentrant Physics2D query')
    local result, seen, f = out or {}, {}, self.factor
    for i = #result, 1, -1 do
        result[i] = nil
    end
    self._querying = true
    local ok, message = pcall(
        self.world.queryBoundingBox,
        self.world,
        x1 * f,
        y1 * f,
        x2 * f,
        y2 * f,
        function(fixture)
            local data = fixture:getUserData()
            if accepts(fixture, filter) and not seen[data.body] and test(fixture) then
                seen[data.body] = true
                result[#result + 1] = data.body
            end
            return true
        end
    )
    self._querying = false
    self:flush()
    if not ok then
        error(message, 0)
    end
    return result
end

function Queries.overlapPoint(self, point, filter, out)
    local x, y, f = point[1], point[2], self.factor
    return overlap(self, x - 0.001, y - 0.001, x + 0.001, y + 0.001, filter, function(fixture)
        return fixture:testPoint(x * f, y * f)
    end, out)
end

local function queryFixture(self, shape, x, y)
    if not self.queryWorld then
        self.queryWorld = katsa.physics.newWorld(0, 0, true)
        self.queryBody = katsa.physics.newBody(self.queryWorld, 0, 0, 'static')
    end
    self.queryBody:setPosition(x * self.factor, y * self.factor)
    if self.queryFixture then
        self.queryFixture:destroy()
    end
    self.queryFixture = katsa.physics.newFixture(self.queryBody, shape)
    shape:release()
    return self.queryFixture
end

local function touches(self, fixture, query)
    local shape = fixture:getShape()
    if shape:getType() ~= 'chain' then
        return katsa.physics.getDistance(fixture, query) <= 0
    end
    -- LÖVE 11.x getDistance checks child zero only. Test every chain segment in
    -- a separate scratch world, leaving the queried solver tree untouched.
    self.chainQueryBody = self.chainQueryBody
        or katsa.physics.newBody(self.queryWorld, 0, 0, 'static')
    self.chainQueryBody:setPosition(fixture:getBody():getPosition())
    self.chainQueryBody:setAngle(fixture:getBody():getAngle())
    local vertices = { shape:getPoints() }
    for i = 1, #vertices - 2, 2 do
        local edge = katsa.physics.newEdgeShape(
            vertices[i],
            vertices[i + 1],
            vertices[i + 2],
            vertices[i + 3]
        )
        local test = katsa.physics.newFixture(self.chainQueryBody, edge)
        edge:release()
        local distance = katsa.physics.getDistance(test, query)
        test:destroy()
        if distance <= 0 then
            return true
        end
    end
    return false
end

function Queries.overlapBox(self, center, size, filter, out)
    assert(not self.released and not self._querying, 'Invalid or reentrant Physics2D query')
    local x, y, w, h = center[1], center[2], size[1] / 2, size[2] / 2
    local query = queryFixture(
        self,
        katsa.physics.newRectangleShape(size[1] * self.factor, size[2] * self.factor),
        x,
        y
    )
    return overlap(self, x - w, y - h, x + w, y + h, filter, function(fixture)
        return touches(self, fixture, query)
    end, out)
end

function Queries.overlapCircle(self, center, radius, filter, out)
    assert(not self.released and not self._querying, 'Invalid or reentrant Physics2D query')
    local x, y = center[1], center[2]
    local query = queryFixture(self, katsa.physics.newCircleShape(radius * self.factor), x, y)
    return overlap(self, x - radius, y - radius, x + radius, y + radius, filter, function(fixture)
        return touches(self, fixture, query)
    end, out)
end

return Queries
