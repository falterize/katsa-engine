-- The `Players` folder: one replicated node per player or bot, with its Nickname and Score as
-- attributes. Clients read the scoreboard from these nodes; only the server writes them.
local Roster = {}
Roster.__index = Roster

function Roster.new(world)
    local self = setmetatable({ entries = {} }, Roster)
    self.folder = world:create('Folder', { name = 'Players', replicated = true })
    self.world = world
    return self
end

-- key: a player id or a bot name. entity: the Avatar object the server tracks for it.
function Roster:add(key, nickname, entity)
    local node = self.world:create('Folder', { name = nickname, replicated = true }, self.folder)
    node:setAttribute('Nickname', nickname)
    node:setAttribute('Score', 0)
    self.entries[key] = { node = node, entity = entity, nickname = nickname }
    return self.entries[key]
end

function Roster:remove(key)
    local entry = self.entries[key]
    if entry then
        entry.node:destroy()
        self.entries[key] = nil
    end
end

function Roster:addScore(key, amount)
    local entry = self.entries[key]
    if entry then
        entry.node:setAttribute('Score', entry.node:getAttribute('Score') + amount)
    end
end

function Roster:resetScores()
    for _, entry in pairs(self.entries) do
        entry.node:setAttribute('Score', 0)
    end
end

function Roster:count()
    local count = 0
    for _ in pairs(self.entries) do
        count = count + 1
    end
    return count
end

-- Returns the key with the highest score, and that score (nil when nobody scored).
function Roster:leader()
    local best, bestScore
    for key, entry in pairs(self.entries) do
        local score = entry.node:getAttribute('Score')
        if score > 0 and (not bestScore or score > bestScore) then
            best, bestScore = key, score
        end
    end
    return best, bestScore
end

return Roster
