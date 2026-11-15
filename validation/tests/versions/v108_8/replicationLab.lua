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
    -- Coins and bots stand on the map's real surface (the arena is not at y = 0).
    local function surfaceAt(x, z)
        local top = 0
        for _, node in ipairs(state.host.maps.current:getDescendants()) do
            if node.className == 'Mesh3D' then
                local p, size = node.position, node.size
                if math.abs(x - p[1]) <= size[1] / 2 and math.abs(z - p[3]) <= size[3] / 2 then
                    top = math.max(top, p[2] + size[2] / 2)
                end
            end
        end
        return top
    end
    local floating = true
    for _, coin in ipairs(state.host.rounds.coins) do
        local p = coin.position
        floating = floating and math.abs(p[2] - surfaceAt(p[1], p[3]) - 0.8) < 0.01
    end
    self:check(floating, 'Every coin floats 0.8 above the surface of the map it was placed on')
    local sample = state.host.rounds.coins[1].position
    self:check(
        math.abs(state.host.maps:heightAt(sample[1], sample[3]) - surfaceAt(sample[1], sample[3])) < 0.01,
        'Bots read the same ground height as the map geometry'
    )
    local HeroTree = require('source.game.characters.heroTree')
    self:check(
        HeroTree.stride(0) == 1 and HeroTree.stride(5) == 2.5 and HeroTree.stride(8) == 3.5,
        'The walk cycle plays at the controller scene rate: 2.5x walking, 3.5x running, idle 1x'
    )
    local set = {}
    local fake = {
        set = function(_, key, value)
            set[key] = value
        end,
    }
    HeroTree.setRate(fake, 0, 0)
    self:check(set.stride == 1 and set.crouchRate == 0, 'Standing still: idle at 1x and the crouch pose holds (rate 0)')
    HeroTree.setRate(fake, -1.5, 3.25)
    self:check(
        set.crouchRate == -1.5 and set.stride < 0,
        'Moving backward plays the walk and crouch clips with a negative multiplier'
    )
    HeroTree.setRate(fake, 2.5, 5)
    self:check(set.stride == 2.5 and set.crouchRate == 2.5, 'Walking forward plays them at the controller rate')
    -- The real tree: a negative rate reaches the tracks, and 0 freezes the crouch clip.
    local engineTree = state.tree.tree
    local function crouchSpeed()
        for _, leaf in ipairs(engineTree.leaves) do
            if leaf.definition.name == 'CrouchClip' then
                return leaf.track.speed
            end
        end
    end
    state.tree:set('stance', 'Crouch')
    HeroTree.setRate(state.tree, -1.5, 3.25)
    for _ = 1, 40 do
        engineTree:update(1 / 60)
    end
    local backward = crouchSpeed()
    HeroTree.setRate(state.tree, 0, 0)
    engineTree:update(1 / 60)
    self:check(
        backward and backward < 0 and crouchSpeed() == 0,
        'The crouch track plays backward when walking backward and stops on the spot'
    )
    local bot = state.host.bots.list[1].avatar
    frames(scene, 30)
    local x, z = bot.x, bot.z
    frames(scene, 6) -- a short step: the heading follows the current direction, not an old turn
    local dx, dz = bot.x - x, bot.z - z
    if dx * dx + dz * dz > 0.04 then
        local heading = math.deg(math.atan2(dx, -dz))
        self:check(
            math.abs((heading - bot.heading + 180) % 360 - 180) < 45,
            'A moving bot faces where it walks (same heading convention as the player)'
        )
    end

    -- Bots race for the same coins, so walk onto a few of them until one is taken.
    local count = #session:node('Coins').children
    for attempt = 1, 3 do
        local coin = session:node('Coins').children[attempt]
        if coin then
            local at = coin.position
            for _, entry in pairs(state.host.roster.entries) do
                if entry.nickname == state.nickname then
                    -- The server moves the avatar and asks the client to follow, as a round does.
                    state.host:teleport(entry.entity, { at[1], at[2], at[3] })
                end
            end
            frames(scene, 20)
        end
    end
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
