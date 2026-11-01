-- Server-side driver: patrols the arena and, once a player's car comes within sight (a radius
-- with a clear line across the pathfinding grid), chases it along an A* route. It produces the
-- same inputs a human would: { throttle, steer, nitro }.
local Plugins = require('source.engine.plugins')
local Pathfinding = Plugins.require('pathfinding')
local Arena = require('scene.scripts.game.arena')

local Bot = {}
Bot.__index = Bot

local function wrap(angle)
    return (angle + 180) % 360 - 180
end

-- options: sightRadius (default 45), seed, replan (seconds between route updates, default 0.5)
function Bot.new(car, options)
    options = options or {}
    local seed = options.seed or 7
    local state = seed
    return setmetatable({
        car = car,
        grid = options.grid or Arena.buildGrid(Pathfinding.Grid),
        sightRadius = options.sightRadius or 45,
        replanEvery = options.replan or 0.5,
        random = function()
            state = (state * 1103515245 + 12345) % 2147483648
            return state / 2147483648
        end,
        mode = 'patrol',
        path = nil,
        sinceReplan = 99,
        stuck = 0,
        reverse = 0,
        target = nil,
        patrolPoint = nil,
    }, Bot)
end

-- Nearest car in `cars` that is driven by a person and visible from the bot.
function Bot:findTarget(cars)
    local car, grid = self.car, self.grid
    local best, bestDistance = nil, self.sightRadius
    local bx, bz = grid:toCell(car.x, car.z)
    for _, other in ipairs(cars) do
        if other ~= car and other:getDriver() and not other.isBot then
            local distance = math.sqrt((other.x - car.x) ^ 2 + (other.z - car.z) ^ 2)
            if distance < bestDistance then
                local ox, oz = grid:toCell(other.x, other.z)
                if grid:lineOfSight(bx, bz, ox, oz) then
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
        local cx, cz = self.grid:toCell(x, z)
        if not self.grid:isBlocked(cx, cz) then
            return { x, z }
        end
    end
    return { 0, -45 }
end

function Bot:plan(x, z)
    self.path = self.grid:findPath(self.car.x, self.car.z, x, z)
    self.sinceReplan = 0
end

-- Returns the input for this tick. `cars` lists every car in the world.
function Bot:think(cars, dt)
    local car = self.car
    self.sinceReplan = self.sinceReplan + dt
    local target, distance = self:findTarget(cars)
    local goalX, goalZ
    if target then
        self.mode, self.target = 'chase', target
        if self.sinceReplan >= self.replanEvery or not self.path then
            self:plan(target.x, target.z)
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
            self:plan(point[1], point[2])
        end
        goalX, goalZ = point[1], point[2]
    end

    -- Follow the route; fall back to heading straight at the goal when no route exists.
    local aimX, aimZ = goalX, goalZ
    if self.path then
        local px, pz = self.path:target(car.x, car.z, nil, 3.5)
        if px then
            aimX, aimZ = px, pz
        end
    end
    local error = wrap(math.deg(math.atan2(aimX - car.x, aimZ - car.z)) - car.heading)
    local input = { throttle = 1, steer = math.max(-1, math.min(1, error / 25)) }
    if math.abs(error) > 75 then
        input.throttle = 0.35
    end
    if self.mode == 'chase' and distance and distance < 10 and car.speed > 12 then
        input.throttle = 0 -- ease off near the target instead of overshooting
    end
    if self.mode == 'chase' and distance and distance > 25 and math.abs(error) < 20 then
        input.nitro = car.nitro > 0.25
    end

    -- Unstick: reversing out of a wall for a moment, steering the other way.
    if self.reverse > 0 then
        self.reverse = self.reverse - dt
        input.throttle, input.steer, input.nitro = -1, -input.steer, false
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
