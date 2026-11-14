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

    state.host.rounds.clock = 0
    frames(scene, 60)
    self:check(
        round:getAttribute('State') == 'Playing' and session:node('Coins') and #session:node('Coins').children > 0,
        'A round starts: coins appear as replicated nodes'
    )
    local matrix = state.player.body.node:getRenderWorldMatrix()
    self:check(math.abs(matrix[4] - 60) < 20, 'The server teleported the local character to the arena')

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
