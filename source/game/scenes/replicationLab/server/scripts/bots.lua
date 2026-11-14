local Arena = require('../../scripts.shared.arena')

-- Server-owned avatars that wander and chase coins, so the lab has company when played alone.
-- A bot is an Avatar entity without an owning player: the server moves it.
local Bots = {}
Bots.__index = Bots

local SPEED = 4

function Bots.new(server, roster, count)
    local self = setmetatable({ server = server, roster = roster, list = {} }, Bots)
    for index = 1, count do
        local name = 'Bot' .. index
        local angle = index / count
        local at = Arena.point(Arena.lobby, Arena.lobbyRadius, angle, 0.6)
        local avatar = server:spawn('Avatar', { name = name, bot = true, x = at[1], y = at[2], z = at[3] })
        roster:add(name, name, avatar)
        self.list[#self.list + 1] = { avatar = avatar, target = at }
    end
    return self
end

-- Where a bot wants to go: the nearest coin during a round, else a point near its lobby spot.
function Bots:aim(bot, coins, home)
    local best, bestDistance
    for _, coin in ipairs(coins) do
        local p = coin.position
        local d = (p[1] - bot.avatar.x) ^ 2 + (p[3] - bot.avatar.z) ^ 2
        if not bestDistance or d < bestDistance then
            best, bestDistance = p, d
        end
    end
    return best or home
end

function Bots:update(dt, rounds)
    local home = Arena.lobby
    for _, bot in ipairs(self.list) do
        local a = bot.avatar
        local target = rounds.state == 'Playing' and self:aim(bot, rounds.coins, home) or bot.target
        local dx, dz = target[1] - a.x, target[3] - a.z
        local distance = math.sqrt(dx * dx + dz * dz)
        if distance > 0.2 then
            local step = math.min(distance, SPEED * dt)
            a.x, a.z = a.x + dx / distance * step, a.z + dz / distance * step
            a.heading = math.deg(math.atan2(dx, dz))
            a.speed = SPEED
        else
            a.speed = 0
        end
    end
end

return Bots
