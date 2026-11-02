-- multiplayerCars rules over real loopback UDP: cars per player, seats and driver authority,
-- the bot chasing within sight, replicated dents and the rewarded-ad nitro refill.
local load = require('validation.tests.katsa.sceneRequire')

return function(T)
    if not pcall(require, 'source.katsa.net') then
        return T.skip('carsGame: network library unavailable')
    end
    katsa = katsa or require('source.katsa')
    local GameServer = load('multiplayerCars', 'scene.scripts.game.gameServer')
    local GameClient = load('multiplayerCars', 'scene.scripts.game.gameClient')
    local Ads = require('source.plugins.ads')
    Ads.configure({ provider = 'mock', mockDuration = 0.1 })
    Ads.load()

    local port = 47950 + math.floor(os.clock() * 1000) % 40
    local link = { latency = 0.02, jitter = 0.005, loss = 0.02 }
    local server = GameServer.new(
        {},
        { port = port, maxPlayers = 4, adCooldown = 5, discoveryPort = port + 1 }
    )
    server.server.options.simulate = link
    server:start()

    local drive = { 0, 0 }
    local function newClient(name, input)
        local client = GameClient.new({}, {
            address = '127.0.0.1',
            port = port,
            name = name,
            input = input,
        })
        client:connect()
        return client
    end
    local one = newClient('Ann', function()
        return { throttle = drive[1], steer = drive[2] }
    end)
    local two = newClient('Bob', function()
        return {}
    end)
    local dt = 1 / 60
    local function run(frames)
        for _ = 1, frames do
            server:update(dt)
            one:update(dt)
            two:update(dt)
        end
    end

    run(180)
    T.check(one:isConnected() and two:isConnected(), 'carsGame: both players connect')
    T.check(
        one.ownWalker ~= nil and two.ownWalker ~= nil and one:getCar() == nil,
        'carsGame: each player starts on foot'
    )
    local walkers, count = 0, 0
    for _ in pairs(one.walkers) do
        walkers = walkers + 1
    end
    for _ in pairs(one.cars) do
        count = count + 1
    end
    T.check(
        walkers == 2 and count == 3 and server.botId ~= nil,
        'carsGame: two walkers, two parked cars and the bot are replicated'
    )
    local oneId, twoId = server.ownCars[one:getPlayerId()], server.ownCars[two:getPlayerId()]
    T.check(oneId and twoId and oneId ~= twoId, 'carsGame: every player has an own car')

    -- Getting in: E next to the own car takes the driver seat and the driver gets authority.
    local entered
    one:sit(oneId, function(seat, reason)
        entered = { seat, reason }
    end)
    run(60)
    T.check(entered and entered[1] == 1, 'carsGame: the own car is entered at the driver seat')
    local seatedId, _, seat = one:getCar()
    T.check(seatedId == oneId and seat == 1, 'carsGame: the seat is replicated to the player')
    T.check(
        server.server:getAuthority(oneId) ~= nil and server.server:getAuthority(twoId) == nil,
        'carsGame: the driven car belongs to its driver, an empty one to the server'
    )

    -- The bot sees a player's car and closes in.
    local bot = server.cars[server.botId]
    local serverOne, serverTwo = server.cars[oneId], server.cars[twoId]
    serverOne.x, serverOne.z = bot.x + 20, bot.z
    local chased = false
    for _ = 1, 60 do
        run(1)
        chased = chased or server.bot.mode == 'chase'
    end
    T.check(chased, 'carsGame: the bot chases a car in its sight radius')

    -- Two floors: a car on the car park deck is reached by a route over the ramp.
    do
        local Arena = load('multiplayerCars', 'scene.scripts.game.arena')
        local g = Arena.garage
        local nav = server.bot.nav
        local path = nav:findPath(20, Arena.ground(20, -30), -30, -42, g.deckY, -48)
        local usesDeck = false
        for index = 1, path and #path.points or 0 do
            usesDeck = usesDeck or path.levels[index] == 2
        end
        T.check(path and usesDeck, 'carsGame: the bot plans a route up to the car park deck')
        local sane = path ~= nil
        for index = 2, path and #path.points or 0 do
            local a, b = path.points[index - 1], path.points[index]
            if path.levels[index] == path.levels[index - 1] and math.abs(b[2] - a[2]) > 0.45 * math.max(1, math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)) then
                sane = false
            end
        end
        T.check(sane, 'carsGame: no route leg is steeper than the ramp')
    end

    -- Seats: Bob's walker is far from Ann's car, then walks up to it.
    local far
    two:sit(oneId, function(seat, reason)
        far = { seat, reason }
    end)
    run(60)
    T.check(far and far[1] == nil and far[2] == 'too far', 'carsGame: a far car cannot be entered')
    -- A client owns its walker, so the move is made where the walker is simulated.
    two.ownWalker.x, two.ownWalker.z = serverOne.x + 3, serverOne.z
    run(30)
    local result
    two:sit(oneId, function(seat, reason)
        result = { seat, reason }
    end)
    run(60)
    T.check(result and result[1] == 2, 'carsGame: a nearby car takes a passenger')
    local joinedId, _, joinedSeat = two:getCar()
    T.check(
        joinedId == oneId and joinedSeat == 2,
        'carsGame: the passenger is seated on every client'
    )

    -- A fourth seat is the limit.
    local car = server.cars[oneId]
    car:sit(901)
    car:sit(902)
    T.check(car:getOccupants() == 4, 'carsGame: four riders fit')
    car.seats[3], car.seats[4] = nil, nil

    -- Dents: an impact reported to the server shows on every replica.
    T.check(
        server:addDent(oneId, serverOne, { x = 0, z = 2.1, nx = 0, nz = -1, speed = 15 }, 1) ~= false,
        'carsGame: an impact dents the car'
    )
    run(30)
    T.check(
        #two.cars[oneId].dents.dents == #serverOne.dents.dents,
        'carsGame: dents are replicated to everyone'
    )

    -- Chat reaches everyone with the sender's name and [HOST] flag; the host alone can kick.
    server.hostPlayer = server.server:getPlayers()[1]
    server:publishHost()
    local hostName = server.hostPlayer.name
    local heard = {}
    two.onChat = function(line)
        heard[#heard + 1] = line
    end
    one:sendChat('  hello there  ')
    for _ = 1, 8 do
        one:sendChat('spam')
    end
    run(60)
    T.check(
        heard[1] and heard[1].text == 'hello there' and heard[1].name == hostName and heard[1].host == true,
        'carsGame: a chat line is trimmed, tagged with the sender and [HOST]'
    )
    T.check(#heard <= 5, 'carsGame: chat is rate limited (' .. #heard .. ' lines)')
    T.check(two.hostId == server.hostPlayer.id, 'carsGame: clients learn who the host is')

    -- Nicknames are unique, ignoring case.
    local clone = newClient(hostName:upper(), function()
        return {}
    end)
    local rejected
    clone.client.disconnected:connect(function(reason)
        rejected = reason
    end)
    for _ = 1, 120 do
        server:update(dt)
        clone:update(dt)
    end
    T.check(
        rejected and tostring(rejected):find('already taken', 1, true),
        'carsGame: a duplicate nickname is rejected (' .. tostring(rejected) .. ')'
    )

    local kicked
    two.client.disconnected:connect(function(reason)
        kicked = reason
    end)
    local denied
    two:kickPlayer(one:getPlayerId(), function(ok, why)
        denied = { ok, why }
    end)
    run(60)
    T.check(denied and denied[1] == false, 'carsGame: only the host can kick')
    local kickResult
    one:kickPlayer(two:getPlayerId(), function(ok)
        kickResult = ok
    end, 'testing')
    run(90)
    T.check(
        kickResult == true and kicked and tostring(kicked):find('Kicked by the host', 1, true),
        'carsGame: the host kicks a player, who is told why (' .. tostring(kicked) .. ')'
    )

    -- Nitro refill for a rewarded ad, rate limited and verified by the server.
    serverOne.nitro = 0
    local refill
    one:requestNitroRefill(function(ok, reason)
        refill = { ok, reason }
    end)
    run(120)
    T.check(
        refill and refill[1] == true and serverOne.nitro == 1,
        'carsGame: a watched ad refills the nitro'
    )
    serverOne.nitro, one.cars[oneId].nitro = 0, 0 -- the driver's client owns the value
    Ads.load()
    local again
    one:requestNitroRefill(function(ok, reason)
        again = { ok, reason }
    end)
    run(120)
    T.check(
        again and again[1] == false and again[2] == 'cooldown' and serverOne.nitro == 0,
        'carsGame: the refill has a cooldown'
    )
    Ads.configure({ provider = 'mock', mockDuration = 0.1, mockSkip = true })
    Ads.load()
    local skipped
    one:requestNitroRefill(function(ok)
        skipped = ok
    end)
    run(60)
    T.check(skipped == false, 'carsGame: a skipped ad refills nothing')

    -- Getting out puts the walker on the ground beside the car and frees the driver seat.
    local left
    one:exitCar(function(ok, x, _, z)
        left = { ok, x, z }
    end)
    run(60)
    T.check(
        left and left[1] == true and one:getCar() == nil,
        'carsGame: leaving the car works and the seat is freed'
    )

    one:disconnect()
    two:disconnect()
    run(60)
    server:stop()
end
