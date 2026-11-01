-- Engine networking over real loopback UDP with simulated latency and loss:
-- handshake, spawn, prediction, interpolation, remotes, relevance and client authority.
local Net = require('source.engine.net')

local function avatar(simulated)
    local definition = {
        fields = { 'position:vec2', 'angle:angle' },
        create = function(_, args)
            return { position = { args.x or 0, args.y or 0 }, angle = 0, name = args.name }
        end,
    }
    if simulated then
        definition.simulate = function(object, input, dt)
            object.position[1] = object.position[1] + (input.x or 0) * 100 * dt
            object.position[2] = object.position[2] + (input.y or 0) * 100 * dt
        end
    end
    return definition
end

local function codecChecks(T)
    local writer = Net.Codec.writer()
    writer:u8(200)
    writer:u16(65000)
    writer:u32(4000000000)
    writer:f32(1.5)
    writer:angle(90)
    writer:value({ a = 1, b = { true, false, 'x' }, c = 'text' })
    writer:values({ 1, nil, 3 }, 3)
    local reader = Net.Codec.reader(writer:finish())
    local ok = reader:u8() == 200 and reader:u16() == 65000 and reader:u32() == 4000000000
    ok = ok and reader:f32() == 1.5 and math.abs(reader:angle() - 90) < 0.01
    local table_ = reader:value()
    ok = ok and table_.a == 1 and table_.b[3] == 'x' and table_.b[2] == false and table_.c == 'text'
    local list, count = reader:values()
    T.check(ok and count == 3 and list[2] == nil and list[3] == 3, 'netGame: codec round trip')
    local truncated = Net.Codec.reader('\1')
    T.check(not pcall(truncated.u32, truncated), 'netGame: truncated message raises')
end

return function(T)
    local okNet = pcall(require, 'source.katsa.net')
    if not okNet then
        return T.skip('netGame: network library unavailable')
    end
    katsa = katsa or require('source.katsa')
    codecChecks(T)

    local random = (function()
        local seed = 12345
        return function()
            seed = (seed * 1103515245 + 12345) % 2147483648
            return seed / 2147483648
        end
    end)()
    local simulate = { latency = 0.04, jitter = 0.01, loss = 0.05, random = random }
    local port = 47600 + math.floor(os.clock() * 1000) % 300
    local server = Net.Server.new({}, { port = port, maxPlayers = 2, simulate = simulate })
    server:define('Avatar', avatar(true))
    server:define('Crate', {
        fields = { 'position:vec2' },
        create = function(_, args)
            return { position = { args.x, args.y }, near = args.near }
        end,
        relevant = function(player, object)
            return object.near == nil or player.data.near == object.near
        end,
    })
    server:define('Beacon', {
        fields = { 'position:vec2' },
        clientAuthoritative = true,
        create = function()
            return { position = { 0, 0 } }
        end,
    })
    local avatars = {}
    server.playerAdded:connect(function(player)
        avatars[player.id] =
            server:spawn('Avatar', { name = player.name, x = 10 * player.id }, player)
    end)
    server:start()

    local function newClient(name, input)
        local client = Net.Client.new({}, {
            address = '127.0.0.1',
            port = port,
            name = name,
            simulate = simulate,
        })
        client:define('Avatar', avatar(true))
        client:define(
            'Crate',
            { fields = { 'position:vec2' }, create = server.registry.definitions.Crate.create }
        )
        client:define('Beacon', {
            fields = { 'position:vec2' },
            clientAuthoritative = true,
            create = server.registry.definitions.Beacon.create,
        })
        client.inputProvider = input
        client:connect()
        return client
    end

    local moveX = 0
    local one = newClient('Ann', function()
        return { x = moveX, y = 0 }
    end)
    local two = newClient('Bob', function()
        return {}
    end)
    local dt = 1 / 60
    local function run(frames)
        for _ = 1, frames do
            server:update(dt)
            one:update(dt)
            if two.host then
                two:update(dt)
            end
        end
    end

    run(120)
    T.check(one:isConnected() and two:isConnected(), 'netGame: both clients complete the handshake')
    T.check(server:getPlayerCount() == 2, 'netGame: server counts two players')
    T.check(one.localPlayer.id ~= two.localPlayer.id, 'netGame: players get distinct ids')
    local count = 0
    for _ in pairs(one.entities) do
        count = count + 1
    end
    T.check(count == 2, 'netGame: each client mirrors both avatars')

    -- Prediction: the local avatar moves immediately; the server follows after latency.
    moveX = 1
    run(60)
    local local1 = one:getObject(server:getNetId(avatars[one.localPlayer.id]))
    local authoritative = avatars[one.localPlayer.id]
    T.check(
        local1.position[1] > authoritative.position[1],
        'netGame: prediction runs ahead of the server'
    )
    T.check(authoritative.position[1] > 10 + 60, 'netGame: server simulates the client input')
    moveX = 0
    run(120)
    T.check(
        math.abs(local1.position[1] - authoritative.position[1]) < 0.05,
        'netGame: reconciliation converges to the server position'
    )
    local replica = two:getObject(server:getNetId(avatars[one.localPlayer.id]))
    T.check(
        math.abs(replica.position[1] - authoritative.position[1]) < 0.05,
        'netGame: remote clients interpolate to the same position'
    )

    -- Remote events and functions.
    local chat = {}
    server:remote('Chat'):onServer(function(player, text)
        server:remote('Chat'):fireAll(player.name, text)
    end)
    one:remote('Chat'):onClient(function(author, text)
        chat[#chat + 1] = 'one:' .. author .. ':' .. text
    end)
    two:remote('Chat'):onClient(function(author, text)
        chat[#chat + 1] = 'two:' .. author .. ':' .. text
    end)
    one:remote('Chat'):fireServer('hi')
    local answer
    server:remote('Sum'):onRequest(function(_, a, b)
        return a + b, 'ok'
    end)
    one:remote('Sum'):request(function(total, status)
        answer = { total, status }
    end, 2, 3)
    run(60)
    T.check(#chat == 2, 'netGame: fireAll reaches both clients')
    T.check(answer and answer[1] == 5 and answer[2] == 'ok', 'netGame: request returns values')

    -- Relevance filter and despawn.
    server:spawn('Crate', { x = 1, y = 1, near = 'A' })
    server:spawn('Crate', { x = 2, y = 2, near = 'B' })
    server:getPlayers()[1].data.near = 'A'
    server:getPlayers()[2].data.near = 'B'
    run(90)
    local function crates(client)
        local n = 0
        for _, entity in pairs(client.entities) do
            n = n + (entity.kind == 'Crate' and 1 or 0)
        end
        return n
    end
    T.check(
        crates(one) == 1 and crates(two) == 1,
        'netGame: relevance filter limits what each client sees'
    )

    -- Client authority.
    local beacon = server:spawn('Beacon', {}, server:getPlayers()[1])
    run(60)
    local ownBeacon
    for _, entity in pairs(one.entities) do
        if entity.kind == 'Beacon' then
            ownBeacon = entity.object
        end
    end
    ownBeacon.position[1], ownBeacon.position[2] = 77, 33
    run(90)
    T.check(
        math.abs(beacon.position[1] - 77) < 0.01,
        'netGame: client-authoritative state reaches the server'
    )

    -- Late join, capacity and leaving.
    local three = newClient('Cy', function()
        return {}
    end)
    for _ = 1, 60 do
        server:update(dt)
        three:update(dt)
    end
    T.check(
        not three:isConnected() and three.rejection == 'Server is full',
        'netGame: full server rejects'
    )
    two:disconnect()
    run(90)
    T.check(server:getPlayerCount() == 1, 'netGame: server notices the leaving player')
    local left = 0
    for _, entity in pairs(one.entities) do
        left = left + (entity.kind == 'Avatar' and 1 or 0)
    end
    T.check(left == 1, 'netGame: the leaving player avatar is removed for others')

    one:disconnect()
    three:disconnect()
    server:stop()
end
