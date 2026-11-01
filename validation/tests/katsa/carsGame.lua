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
    local oneId, oneCar, oneSeat = one:getCar()
    local twoId, twoCar = two:getCar()
    T.check(
        oneId and twoId and oneId ~= twoId and oneSeat == 1,
        'carsGame: each player starts as a driver'
    )
    local count = 0
    for _ in pairs(one.cars) do
        count = count + 1
    end
    T.check(
        count == 3 and server.botId ~= nil,
        'carsGame: two player cars and the bot are replicated'
    )

    -- The bot sees a player's car and closes in.
    local bot = server.cars[server.botId]
    local function distanceTo(netId)
        local other = server.cars[netId]
        return math.sqrt((bot.x - other.x) ^ 2 + (bot.z - other.z) ^ 2)
    end
    local nearest = math.min(distanceTo(oneId), distanceTo(twoId))
    local closest, chased = nearest, false
    for _ = 1, 240 do
        run(1)
        chased = chased or server.bot.mode == 'chase'
        closest = math.min(closest, distanceTo(oneId), distanceTo(twoId))
    end
    T.check(chased, 'carsGame: the bot chases a car in its sight radius')
    T.check(closest < 15, 'carsGame: the bot closes in on the car')

    -- Driving moves the authoritative car and prediction agrees.
    local serverOne = server.cars[oneId]
    local startZ = serverOne.z
    drive = { 1, 0 }
    run(120)
    T.check(
        serverOne.speed > 5 and serverOne.z ~= startZ,
        'carsGame: the driver input moves the server car'
    )
    drive = { 0, 0 }
    run(180)

    -- Seats: Bob joins Ann's car, which needs to be close and have room.
    local serverTwo = server.cars[twoId]
    serverTwo:setPose(serverOne.x + 4, serverOne.z, 0)
    serverTwo.speed = 0
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
    T.check(
        server.server:getAuthority(oneId) ~= nil and server.server:getAuthority(twoId) == nil,
        'carsGame: the abandoned car has no driver'
    )

    serverTwo:setPose(60, 60, 0)
    local far
    one:sit(twoId, function(seat, reason)
        far = { seat, reason }
    end)
    run(60)
    T.check(far and far[1] == nil, 'carsGame: nobody can sit in a car that is not theirs to reach')

    -- A fourth seat is the limit.
    local car = server.cars[oneId]
    car:sit(901)
    car:sit(902)
    T.check(car:getOccupants() == 4, 'carsGame: four riders fit')
    car.seats[3], car.seats[4] = nil, nil

    -- Dents: drive Ann's car into the wall and watch the replicas change.
    serverOne:setPose(serverOne.x, 50, 0)
    serverOne.speed = 25
    drive = { 1, 0 }
    run(180)
    drive = { 0, 0 }
    T.check(#serverOne.dents.dents > 0, 'carsGame: hitting a wall dents the car')
    run(30)
    T.check(
        #two.cars[oneId].dents.dents == #serverOne.dents.dents,
        'carsGame: dents are replicated to everyone'
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
    serverOne.nitro = 0
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

    one:disconnect()
    two:disconnect()
    run(60)
    server:stop()
end
