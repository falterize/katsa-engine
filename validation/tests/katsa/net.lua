-- katsa.net over loopback: connection, channels, large payloads, disconnect and LAN discovery.
return function(T)
    local ok, Net = pcall(require, 'source.katsa.net')
    if not ok then
        return T.skip('net: unavailable (' .. tostring(Net) .. ')')
    end
    local port = 47000 + math.floor(os.clock() * 1000) % 500
    local server = Net.listen({ port = port, maxPeers = 4 })
    local client = Net.connect({ address = '127.0.0.1', port = port })

    local serverPeer, connected, received = nil, false, {}
    -- Runs both hosts until `done()` or about two seconds pass.
    local function pump(done, onServer, onClient)
        local deadline = os.clock() + 2
        while os.clock() < deadline and not done() do
            for event in server:poll(0.005) do
                if event.type == 'connect' then
                    serverPeer = event.peer
                end
                if onServer then
                    onServer(event)
                end
            end
            for event in client:poll() do
                if event.type == 'connect' then
                    connected = true
                end
                if onClient then
                    onClient(event)
                end
            end
        end
    end

    pump(function()
        return connected and serverPeer
    end)
    T.check(connected and serverPeer ~= nil, 'net: client connects to the listening host')
    T.check(client.server:isConnected(), 'net: peer reports the connected state')
    T.check(server:getPeerCount() == 1, 'net: server counts one peer')

    local echoed
    client.server:send('hello', 1)
    pump(function()
        return echoed
    end, function(event)
        if event.type == 'receive' then
            event.peer:send(event.data .. '!', event.channel)
        end
    end, function(event)
        if event.type == 'receive' then
            echoed = event
        end
    end)
    T.check(echoed and echoed.data == 'hello!' and echoed.channel == 1, 'net: reliable echo')

    -- Ordered delivery on the reliable channel.
    for index = 1, 50 do
        client.server:send(tostring(index), 1)
    end
    pump(function()
        return #received >= 50
    end, function(event)
        if event.type == 'receive' then
            received[#received + 1] = event.data
        end
    end)
    local ordered = #received == 50
    for index = 1, #received do
        ordered = ordered and received[index] == tostring(index)
    end
    T.check(ordered, 'net: reliable channel preserves order')

    -- A payload larger than one MTU is fragmented and reassembled.
    local big = string.rep('katsa', 40000)
    local bigReceived
    client.server:send(big, 1)
    pump(function()
        return bigReceived
    end, function(event)
        if event.type == 'receive' and #event.data == #big then
            bigReceived = event.data
        end
    end)
    T.check(bigReceived == big, 'net: 200 KB reliable payload arrives intact')

    local fast
    client.server:send('state', 3)
    pump(function()
        return fast
    end, function(event)
        if event.type == 'receive' then
            fast = event
        end
    end)
    T.check(
        fast and fast.channel == 3 and fast.data == 'state',
        'net: unreliable channel delivers on loopback'
    )
    T.check(
        client.server:getPing() >= 0 and client.server:getLoss() >= 0,
        'net: ping and loss are readable'
    )

    local address, remotePort = serverPeer:getAddress()
    T.check(address == '127.0.0.1' and remotePort > 0, 'net: server sees the client address')

    local disconnected
    client.server:disconnect(7)
    pump(function()
        return disconnected
    end, function(event)
        if event.type == 'disconnect' then
            disconnected = event
        end
    end)
    T.check(disconnected and disconnected.reason == 7, 'net: disconnect carries its reason')

    -- LAN discovery.
    local announcer = Net.lan.announce({ port = port + 1, info = 'Test room|' .. port })
    local browser = Net.lan.browse({ port = port + 1 })
    browser:refresh('127.0.0.1')
    local list = {}
    local deadline = os.clock() + 2
    while os.clock() < deadline and #list == 0 do
        announcer:update()
        list = browser:update()
    end
    T.check(
        #list == 1 and list[1].info == 'Test room|' .. port,
        'net: LAN browser lists the announced server'
    )
    announcer:close()
    browser:close()
    client:close()
    server:close()
end
