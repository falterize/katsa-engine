-- ENet's unreliable-packet throttle must stay off, and state packets use the unreliable channel
-- only when the native library guarantees that.
local Channels = require('source.engine.net.channels')
local Protocol = require('source.engine.net.protocol')

local Module = {}

function Module.run(self)
    self:check(katsa.net.unthrottled() == true, 'the native net library keeps the throttle off')
    self:check(Channels.state() == Protocol.SEQUENCED, 'state packets use the sequenced channel')
    local server = katsa.net.listen({ port = 47321 })
    local client = katsa.net.connect({ address = '127.0.0.1', port = 47321 })
    local peer
    local deadline = katsa.timer.getTime() + 2
    while not peer and katsa.timer.getTime() < deadline do
        for event in server:poll() do
            peer = peer or (event.type == 'connect' and event.peer or nil)
        end
        for _ in client:poll() do
        end
        server:flush()
        client:flush()
    end
    self:check(peer ~= nil, 'a loopback peer connects')
    local received = 0
    if peer then
        for _ = 1, 60 do
            peer:send('state', Protocol.SEQUENCED)
            server:flush()
            local until_ = katsa.timer.getTime() + 0.004
            while katsa.timer.getTime() < until_ do
            end
            for event in client:poll() do
                received = received + (event.type == 'receive' and 1 or 0)
            end
        end
    end
    self:check(received >= 57, 'unreliable state packets are delivered on loopback (' .. received .. '/60)')
    client:close()
    server:close()
end

return Module
