-- Server-side driver: patrols the arena and, once a player's car comes within sight (a radius
-- with a clear line across the pathfinding grid), chases it along an A* route. It produces the
-- same inputs a human would: { throttle, steer, nitro }.
local Plugins = require('source.engine.plugins')
local Pathfinding = Plugins.require('pathfinding')
local Arena = require('./arena')

local Bot = {}
Bot.__index = Bot

local function wrap(angle)
    return (angle + 180) % 360 - 180
end

-- options: sightRadius (default 45), seed, replan (seconds between route updates, default 0.5),
-- nav (a Layered navigation map; built from the arena when omitted).
function Bot.new(car, options)
    options = options or {}
    local seed = options.seed or 7
    local state = seed
    return setmetatable({
        car = car,
        nav = options.nav or Arena.buildNav(Pathfinding),
        sightRadius = options.sightRadius or 45,
        replanEvery = options.replan or 0.5,
        random = function()
            state = (state * 1103515245 + 12345) % 2147483648
            return state / 2147483648
        end,
        mode = 'patrol',
        path = nil,
        sinceReplan = 99,
        clock = 0, -- seconds of thinking time, ages the cached floor routes
        routes = setmetatable({}, { __mode = 'k' }), -- other car -> { at, ok, path }
        stuck = 0,
        reverse = 0,
        target = nil,
        patrolPoint = nil,
    }, Bot)
end

-- The floor a car is on (1 = ground, 2 = car park deck), from its height above the surface.
function Bot:levelOf(car)
    return self.nav:levelAt(car.x, car.y - 0.6, car.z, 2.5)
end

-- Nearest car driven by a person that the bot can reach: on the same floor it needs a clear line
-- across the grid, on another floor the route itself must be short enough.
function Bot:findTarget(cars)
    local car, nav = self.car, self.nav
    local level = self:levelOf(car)
    local best, bestDistance = nil, self.sightRadius
    if not level then
        return nil
    end
    local bx, bz = nav:toCell(car.x, car.z)
    for _, other in ipairs(cars) do
        if other ~= car and other:getDriver() and not other.isBot then
            local distance = math.sqrt((other.x - car.x) ^ 2 + (other.z - car.z) ^ 2)
            local otherLevel = self:levelOf(other)
            if distance < bestDistance and otherLevel then
                local visible
                if otherLevel == level then
                    local ox, oz = nav:toCell(other.x, other.z)
                    visible = nav.levels[level]:lineOfSight(bx, bz, ox, oz)
                else
                    -- Another floor: reachable if the route is not much longer than the sight radius.
                    -- A route search per car per tick was the bulk of the bot cost, so the answer
                    -- is kept for one replan period.
                    local route = self.routes[other]
                    if not route or self.clock - route.at >= self.replanEvery then
                        local path =
                            nav:findPath(car.x, car.y - 0.6, car.z, other.x, other.y - 0.6, other.z)
                        route = {
                            at = self.clock,
                            ok = path ~= nil and path.length < self.sightRadius * 2,
                            path = path,
                        }
                        self.routes[other] = route
                    end
                    visible = route.ok
                end
                if visible then
                    best, bestDistance = other, distance
                end
            end
        end
    end
    return best, bestDistance
end

function Bot:pickPatrolPoint()
    local half = Arena.size / 2 - 10
    for _ = 1, 30 do
        local x = (self.random() * 2 - 1) * half
        local z = (self.random() * 2 - 1) * half
        local cx, cz = self.nav:toCell(x, z)
        if not self.nav:isBlocked(1, cx, cz) then
            return { x, z }
        end
    end
    return { 0, -45 }
end

function Bot:plan(x, y, z, fresh)
    local car = self.car
    -- `fresh` is a route found a moment ago for this very target: use it instead of searching again.
    self.path = fresh or self.nav:findPath(car.x, car.y - 0.6, car.z, x, y - 0.6, z)
    self.sinceReplan = 0
end

-- Aims at the farthest upcoming waypoint that is still on this floor and within a short look-ahead,
-- so the car cuts corners but never aims through a wall behind the next turn.
function Bot:aimPoint()
    local path, car = self.path, self.car
    if not path then
        return nil
    end
    local px, py, pz = path:target(car.x, car.y, car.z, 3.5)
    if not px then
        return nil
    end
    return px, pz
end

-- Returns the input for this tick. `cars` lists every car in the world.
function Bot:think(cars, dt)
    local car = self.car
    self.sinceReplan = self.sinceReplan + dt
    self.clock = self.clock + dt
    local target, distance = self:findTarget(cars)
    local goalX, goalZ
    if target then
        self.mode, self.target = 'chase', target
        if self.sinceReplan >= self.replanEvery or not self.path then
            local route = self.routes[target]
            local fresh = route and route.at == self.clock and route.path or nil
            self:plan(target.x, target.y, target.z, fresh)
        end
        goalX, goalZ = target.x, target.z
    else
        if self.mode == 'chase' then
            self.mode, self.path, self.patrolPoint = 'patrol', nil, nil
        end
        local point = self.patrolPoint
        if not point or (point[1] - car.x) ^ 2 + (point[2] - car.z) ^ 2 < 36 then
            point = self:pickPatrolPoint()
            self.patrolPoint = point
            self.path = nil
        end
        if not self.path or self.path:isFinished() then
            self:plan(point[1], Arena.ground(point[1], point[2]) + 0.6, point[2])
        end
        goalX, goalZ = point[1], point[2]
    end

    local aimX, aimZ = self:aimPoint()
    aimX, aimZ = aimX or goalX, aimZ or goalZ
    local error = wrap(math.deg(math.atan2(aimX - car.x, aimZ - car.z)) - car.heading)
    local input = { throttle = 1, steer = math.max(-1, math.min(1, error / 25)) }
    -- Slow for sharp turns so the car does not slide into the wall it is turning around.
    local sharp = math.abs(error)
    if sharp > 75 then
        input.throttle = 0.35
    elseif sharp > 40 and car.speed > 14 then
        input.throttle = 0.2
    end
    -- On the deck there is little room: keep the speed down.
    if self:levelOf(car) == 2 and car.speed > 11 then
        input.throttle = 0
    end
    if self.mode == 'chase' and distance and distance < 10 and car.speed > 12 then
        input.throttle = 0
    end
    if self.mode == 'chase' and distance and distance > 25 and sharp < 20 then
        input.nitro = car.nitro > 0.25
    end

    -- Unstick: reversing out of a wall for a moment, steering the other way, then replan.
    if self.reverse > 0 then
        self.reverse = self.reverse - dt
        input.throttle, input.steer, input.nitro = -1, -input.steer, false
        self.path = nil
    elseif math.abs(car.speed) < 1 then
        self.stuck = self.stuck + dt
        if self.stuck > 1.2 then
            self.stuck, self.reverse = 0, 1
        end
    else
        self.stuck = 0
    end
    return input
end

return Bot
