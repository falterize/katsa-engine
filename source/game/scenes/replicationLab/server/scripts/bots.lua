local Arena = require('../../scripts.shared.arena')

-- Server-owned avatars that wander and chase coins, so the lab has company when played alone.
-- A bot is an Avatar entity without an owning player: the server moves it.
local Bots = {}
Bots.__index = Bots

local SPEED = 4.2
local ACCELERATION = 9 -- units per second squared
local TURN_RATE = 420 -- degrees per second
local SEPARATION = 1.6
local RISE = 7 -- how fast a bot climbs onto higher ground, units per second

-- The same heading convention as the player's character: degrees, 0 faces -Z, positive turns to +X.
local function headingOf(dx, dz)
    return math.deg(math.atan2(dx, -dz))
end

-- Turns `current` toward `target` by at most `limit` degrees, the short way round.
local function turn(current, target, limit)
    local difference = (target - current + 180) % 360 - 180
    return current + math.max(-limit, math.min(limit, difference))
end

function Bots.new(server, roster, count, maps)
    local self = setmetatable({ server = server, roster = roster, maps = maps, list = {} }, Bots)
    for index = 1, count do
        local name = 'Bot' .. index
        local angle = index / count
        local at = Arena.point(Arena.lobby, Arena.lobbyRadius, angle, 0.6)
        local avatar = server:spawn('Avatar', { name = name, bot = true, x = at[1], y = at[2], z = at[3] })
        roster:add(name, name, avatar)
        self.list[#self.list + 1] = { avatar = avatar, target = at, pause = math.random() * 2, v = 0 }
    end
    return self
end

-- A random spot in the lobby for idle wandering.
local function wanderPoint()
    return Arena.point(Arena.lobby, Arena.lobbyRadius, math.random(), 0.15 + 0.8 * math.random())
end

-- The coin a bot chases: kept until it is taken, chosen among the nearest few so the bots do not
-- all run for the same one.
function Bots:coinFor(bot, coins)
    if bot.coin and not bot.coin.destroyed then
        return bot.coin
    end
    local candidates, a = {}, bot.avatar
    for _, coin in ipairs(coins) do
        local p = coin.position
        candidates[#candidates + 1] = { coin = coin, distance = (p[1] - a.x) ^ 2 + (p[3] - a.z) ^ 2 }
    end
    table.sort(candidates, function(left, right)
        return left.distance < right.distance
    end)
    local pick = candidates[math.min(#candidates, math.random(1, 3))]
    bot.coin = pick and pick.coin
    return bot.coin
end

function Bots:update(dt, rounds)
    for _, bot in ipairs(self.list) do
        local a = bot.avatar
        local goal
        if rounds.state == 'Playing' then
            local coin = self:coinFor(bot, rounds.coins)
            goal = coin and coin.position
        else
            bot.coin = nil
            if bot.pause > 0 then
                bot.pause = bot.pause - dt
            else
                goal = bot.target
            end
        end
        local wantX, wantZ, wanted = 0, 0, 0
        if goal then
            local dx, dz = goal[1] - a.x, goal[3] - a.z
            local distance = math.sqrt(dx * dx + dz * dz)
            if distance < 0.4 and rounds.state ~= 'Playing' then
                bot.target, bot.pause = wanderPoint(), 0.8 + math.random() * 2.2
            elseif distance > 0.05 then
                wantX, wantZ = dx / distance, dz / distance
                -- Slow down when arriving so the bot does not stop dead.
                wanted = math.min(SPEED, math.max(1.2, distance * 2.5))
            end
        end
        -- Keep a little distance from the other avatars.
        for _, other in ipairs(self.list) do
            if other ~= bot then
                local ox, oz = a.x - other.avatar.x, a.z - other.avatar.z
                local d = math.sqrt(ox * ox + oz * oz)
                if d > 0.001 and d < SEPARATION then
                    local push = (SEPARATION - d) / SEPARATION
                    wantX, wantZ = wantX + ox / d * push, wantZ + oz / d * push
                end
            end
        end
        local length = math.sqrt(wantX * wantX + wantZ * wantZ)
        if wanted > 0 and length > 0.001 then
            local target = headingOf(wantX, wantZ)
            a.heading = turn(a.heading, target, TURN_RATE * dt)
            -- Move along the facing direction, slower while the turn is still large.
            local misalignment = math.abs((target - a.heading + 180) % 360 - 180)
            wanted = wanted * math.max(0.25, 1 - misalignment / 120)
        else
            wanted = 0
        end
        bot.v = bot.v + math.max(-ACCELERATION * 1.5 * dt, math.min(ACCELERATION * dt, wanted - bot.v))
        local rad = math.rad(a.heading)
        a.x = a.x + math.sin(rad) * bot.v * dt
        a.z = a.z - math.cos(rad) * bot.v * dt
        a.speed = bot.v
        -- Stand on the map: rise and fall toward the ground height (that shows as a jump).
        local ground = self.maps:heightAt(a.x, a.z) + 1
        local climb = math.max(-RISE * dt * 1.5, math.min(RISE * dt, ground - a.y))
        a.y = a.y + climb
        a.air = math.abs(ground - a.y) > 0.15
    end
end

return Bots
