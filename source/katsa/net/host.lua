-- A network host: a listening server or a connecting client. Call poll() every frame.
local ffi = require('ffi')
local Binding = require('source.katsa.net.binding')
local Peer = require('source.katsa.net.peer')

local Host = {}
Host.__index = Host

local EVENTS = { 'connect', 'disconnect', 'receive' }

function Host.new(handle, channels, isServer)
    return setmetatable({
        handle = ffi.gc(handle, Binding.lib().knet_host_destroy),
        channels = channels,
        isServer = isServer,
        peers = {},
        count = 0,
        event = ffi.new('KNetEvent[1]'),
    }, Host)
end

function Host:getPeer(id)
    local peer = self.peers[id]
    if not peer then
        peer = Peer.new(self, id)
        self.peers[id] = peer
    end
    return peer
end

-- Iterator over pending events: { type = 'connect'|'disconnect'|'receive', peer, channel, data,
-- reason }. `data` is a Lua string copy of the payload. `timeout` waits up to that many seconds
-- for the first event (default 0, non-blocking).
function Host:poll(timeout)
    local lib, event = Binding.lib(), self.event
    local wait = math.floor((timeout or 0) * 1000)
    return function()
        if not self.handle then
            return nil
        end
        local status = lib.knet_service(self.handle, wait, event)
        wait = 0
        if status <= 0 or event[0].type == 0 then
            return nil
        end
        local raw = event[0]
        local item = { type = EVENTS[raw.type], peer = self:getPeer(raw.peer) }
        if raw.type == 3 then
            item.channel = raw.channel + 1
            item.data = ffi.string(raw.payload, raw.length)
        elseif raw.type == 2 then
            item.reason = raw.data
            self.peers[raw.peer] = nil
        end
        return item
    end
end

function Host:broadcast(data, channel)
    local flags = ({ [1] = 1, [2] = 0, [3] = 2 })[channel or 1]
    Binding.lib().knet_broadcast(self.handle, (channel or 1) - 1, data, #data, flags)
end

function Host:flush()
    Binding.lib().knet_flush(self.handle)
end

function Host:getPeerCount()
    return Binding.lib().knet_connected_count(self.handle)
end

function Host:close()
    if self.handle then
        for id in pairs(self.peers) do
            Binding.lib().knet_disconnect(self.handle, id, 0, 1)
        end
        Binding.lib().knet_flush(self.handle)
        ffi.gc(self.handle, nil)
        Binding.lib().knet_host_destroy(self.handle)
        self.handle, self.peers = nil, {}
    end
end

return Host
