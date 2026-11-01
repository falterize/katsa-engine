-- One remote endpoint of a Host. Channels are 1-based: 1 reliable and ordered, 2 unreliable but
-- sequenced (stale packets are dropped), 3 unreliable and unsequenced.
local ffi = require('ffi')
local Binding = require('source.katsa.net.binding')

local Peer = {}
Peer.__index = Peer

local FLAGS = { [1] = 1, [2] = 0, [3] = 2 }
local STATES = {
    [0] = 'disconnected',
    [1] = 'connecting',
    [2] = 'acknowledging',
    [3] = 'pending',
    [4] = 'succeeded',
    [5] = 'connected',
    [6] = 'disconnect-later',
    [7] = 'disconnecting',
    [8] = 'acknowledging-disconnect',
    [9] = 'zombie',
}

function Peer.new(host, id)
    return setmetatable({ host = host, id = id }, Peer)
end

function Peer:send(data, channel)
    channel = channel or 1
    local flags = assert(FLAGS[channel], 'Channel must be 1, 2 or 3')
    assert(type(data) == 'string', 'Network data must be a string')
    local lib = Binding.lib()
    return lib.knet_send(self.host.handle, self.id, channel - 1, data, #data, flags) == 0
end

function Peer:disconnect(reason, immediately)
    Binding.lib().knet_disconnect(self.host.handle, self.id, reason or 0, immediately and 1 or 0)
end

function Peer:getState()
    return STATES[Binding.lib().knet_peer_state(self.host.handle, self.id)] or 'unknown'
end

function Peer:isConnected()
    return self:getState() == 'connected'
end

-- Round trip time in milliseconds.
function Peer:getPing()
    return Binding.lib().knet_stats(self.host.handle, self.id, nil)
end

-- Fraction of packets lost, 0..1.
function Peer:getLoss()
    local loss = ffi.new('double[1]')
    Binding.lib().knet_stats(self.host.handle, self.id, loss)
    return loss[0]
end

function Peer:getAddress()
    local buffer, port = ffi.new('char[64]'), ffi.new('int[1]')
    if Binding.lib().knet_peer_address(self.host.handle, self.id, buffer, 64, port) ~= 0 then
        return nil
    end
    return ffi.string(buffer), port[0]
end

return Peer
