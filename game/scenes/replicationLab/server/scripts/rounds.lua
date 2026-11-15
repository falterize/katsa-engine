local Arena = require('../../scripts.shared.arena')

-- The round system. One replicated `Round` node carries the state as attributes (State, Timer,
-- Message); the coins of a round are replicated nodes the server creates and destroys. Clients
-- only read; they ask for nothing and cannot change a score.
--   Intermission -> Playing (a random map from ServerStorage/Maps is cloned in, everyone is
--   teleported onto it, coins appear)
--   Playing -> Results (all coins taken or time over) -> Intermission (everyone goes back)
local Rounds = {}
Rounds.__index = Rounds

local INTERMISSION, PLAYING, RESULTS = 8, 40, 5
local PICKUP_RANGE = 1.3

-- world: the server world. roster: Roster. teleport(entity, position): moves a player or bot.
-- say(text): a line in everybody's chat.
function Rounds.new(world, roster, teleport, say, maps)
    local self = setmetatable({
        world = world,
        roster = roster,
        teleport = teleport,
        say = say,
        maps = maps,
        coins = {},
        clock = INTERMISSION,
    }, Rounds)
    self.node = world:create('Folder', { name = 'Round', replicated = true })
    self.coinFolder = world:create('Folder', { name = 'Coins', replicated = true })
    self:setState('Intermission', 'Waiting for the round')
    return self
end

function Rounds:setState(state, message)
    self.state = state
    self.node:setAttribute('State', state)
    self.node:setAttribute('Message', message)
end

local function ring(count, index)
    return index / count
end

function Rounds:spawnCoins(points)
    for index, position in ipairs(points) do
        local coin = self.world:create('Mesh3D', {
            name = 'Coin' .. index,
            kind = 'sphere',
            position = position,
            size = { 0.7, 0.7, 0.7 },
            color = { 1, 0.8, 0.16, 1 },
            replicated = true,
            replicatedProperties = { 'kind', 'position', 'size', 'color' },
        }, self.coinFolder)
        self.coins[#self.coins + 1] = coin
    end
end

function Rounds:clearCoins()
    for _, coin in ipairs(self.coins) do
        if not coin.destroyed then
            coin:destroy()
        end
    end
    self.coins = {}
end

-- Moves everybody to `center`, spread around a ring so they do not stack.
function Rounds:gather(center, radius, height)
    local total, index = self.roster:count(), 0
    for _, entry in pairs(self.roster.entries) do
        index = index + 1
        local at = Arena.point(center, radius, (index + 0.5) / total, 0.8)
        at[2] = height or at[2]
        self.teleport(entry.entity, at)
    end
end

function Rounds:start()
    self.roster:resetScores()
    local _, points, title = self.maps:spawn()
    self:spawnCoins(points)
    -- Dropped from above so nobody starts inside a wall or block of the map.
    self:gather(Arena.arena, Arena.arenaRadius * 0.4, 5)
    self.clock = PLAYING
    self.node:setAttribute('Map', title)
    self:setState('Playing', 'Collect the coins')
    self.say('Round started on ' .. title .. ': collect the coins!')
end

function Rounds:finish()
    local key, score = self.roster:leader()
    local message = key and ('%s wins with %d coins'):format(self.roster.entries[key].nickname, score)
        or 'Nobody collected a coin'
    self:clearCoins()
    self.clock = RESULTS
    self:setState('Results', message)
    self.say(message)
end

function Rounds:returnToLobby()
    self.maps:clear()
    self.node:setAttribute('Map', '')
    self:gather(Arena.lobby, Arena.lobbyRadius * 0.5)
    self.clock = INTERMISSION
    self:setState('Intermission', 'Next round soon')
end

-- A coin belongs to whoever stands within reach of it first; the server reads the avatars' poses.
function Rounds:collect()
    for index = #self.coins, 1, -1 do
        local coin = self.coins[index]
        local p = coin.position
        for key, entry in pairs(self.roster.entries) do
            local a = entry.entity
            local dx, dy, dz = a.x - p[1], a.y - p[2], a.z - p[3]
            if dx * dx + dy * dy + dz * dz < PICKUP_RANGE * PICKUP_RANGE then
                coin:destroy()
                table.remove(self.coins, index)
                self.roster:addScore(key, 1)
                break
            end
        end
    end
end

function Rounds:update(dt)
    self.clock = self.clock - dt
    self.node:setAttribute('Timer', math.max(0, math.ceil(self.clock)))
    if self.state == 'Playing' then
        self:collect()
        if #self.coins == 0 or self.clock <= 0 then
            self:finish()
        end
    elseif self.clock <= 0 then
        if self.state == 'Intermission' then
            self:start()
        else
            self:returnToLobby()
        end
    end
end

return Rounds
