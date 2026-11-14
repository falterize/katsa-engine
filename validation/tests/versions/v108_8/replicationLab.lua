-- The replicationLab scene end to end: a server in the same process, a client joined to it, rounds,
-- teleports, coins, the scoreboard, chat and nicknames, all through the network.
local Application = require('source.game.runtime.application')

local Module = {}

local function frames(scene, count)
    for _ = 1, count do
        scene:update(1 / 60, 1 / 60)
    end
end

function Module.run(self)
    local scene = Application.new(self.manager, 'replicationLab')
    scene:load()
    local state = scene.demo
    frames(scene, 90)
    local session = state.session
    local round = session:node('Round')
    self:check(
        round and round:getAttribute('State') == 'Intermission' and session:node('Platform') ~= nil,
        'The Round node and the moving Platform arrive from the server'
    )
    local players = session:node('Players')
    self:check(
        players and #players.children >= 4,
        'Every player and bot has a Players node (nickname and score attributes)'
    )
    local x0 = session:node('Platform').position[1]
    frames(scene, 60)
    self:check(session:node('Platform').position[1] ~= x0, 'A property the server moves follows on the client')

    -- Standing on the platform carries the character along with it.
    local platform = session:node('Platform')
    state:teleport(platform.position[1], 3, platform.position[3])
    frames(scene, 60)
    local function offset()
        return state.player.body.node:getRenderWorldMatrix()[4] - platform.position[1]
    end
    local before, platformBefore = offset(), platform.position[1]
    frames(scene, 90)
    self:check(
        math.abs(platform.position[1] - platformBefore) > 1.5 and math.abs(offset() - before) < 1.2,
        'The character stands on the moving platform and is carried by it'
    )

    state.host.rounds.clock = 0
    frames(scene, 60)
    self:check(
        round:getAttribute('State') == 'Playing' and session:node('Coins') and #session:node('Coins').children > 0,
        'A round starts: coins appear as replicated nodes'
    )
    local matrix = state.player.body.node:getRenderWorldMatrix()
    self:check(math.abs(matrix[4] - 60) < 20, 'The server teleported the local character to the arena')

    local title = round:getAttribute('Map')
    self:check(
        title and title ~= '' and session:node('Map') ~= nil and #session:node('Map').children > 3,
        'Each round clones a random map from ServerStorage/Maps and replicates it'
    )
    local bot = state.host.bots.list[1].avatar
    local x, z = bot.x, bot.z
    frames(scene, 30)
    local dx, dz = bot.x - x, bot.z - z
    if dx * dx + dz * dz > 1 then
        local heading = math.deg(math.atan2(dx, -dz))
        self:check(
            math.abs((heading - bot.heading + 180) % 360 - 180) < 45,
            'A moving bot faces where it walks (same heading convention as the player)'
        )
    end

    local coin = session:node('Coins').children[1]
    local count = #session:node('Coins').children
    local at = coin.position
    state:teleport(at[1], at[2], at[3])
    frames(scene, 40)
    self:check(#session:node('Coins').children < count, 'Touching a coin makes the server delete it everywhere')

    state.host.rounds.clock = 0
    frames(scene, 90)
    self:check(round:getAttribute('State') == 'Results', 'The round ends with a result message')

    local heard
    state.chat.add = function(_, author, text)
        heard = author .. ':' .. text
    end
    session:sendChat('hello')
    frames(scene, 30)
    self:check(heard == state.nickname .. ':hello', 'Chat reaches everybody with the server-checked nickname')
    scene:release()
end

return Module
