-- katsa.net: UDP networking (ENet) with reliable/unreliable channels and LAN discovery.
--
--   local host = katsa.net.listen({ port = 7777, maxPeers = 16 })
--   local client = katsa.net.connect({ address = '127.0.0.1', port = 7777 })
--   for event in host:poll() do ... end
local ffi = require('ffi')
local Binding = require('source.katsa.net.binding')
local Host = require('source.katsa.net.host')

local Net = {}

local DEFAULT_CHANNELS = 3

-- options: port (0 picks a free port), address (bind address, default all), maxPeers, channels.
function Net.listen(options)
    options = options or {}
    local channels = options.channels or DEFAULT_CHANNELS
    local handle = Binding.lib().knet_host_create(
        options.address,
        options.port or 0,
        options.maxPeers or 32,
        channels
    )
    assert(handle ~= nil, 'Could not open port ' .. tostring(options.port))
    return Host.new(handle, channels, true)
end

-- options: address, port, channels, timeout (seconds before an unanswered connect gives up).
-- The returned Host has `server`, the Peer of the remote server.
function Net.connect(options)
    local channels = options.channels or DEFAULT_CHANNELS
    local lib = Binding.lib()
    local handle = lib.knet_host_create(nil, -1, 1, channels)
    assert(handle ~= nil, 'Could not create a client host')
    local host = Host.new(handle, channels, false)
    local id = lib.knet_connect(handle, options.address or '127.0.0.1', options.port, channels)
    if id < 0 then
        host:close()
        error('Could not resolve ' .. tostring(options.address))
    end
    host.server = host:getPeer(id)
    local ms = math.floor((options.timeout or 5) * 1000)
    lib.knet_set_timeout(handle, id, 32, ms, ms * 2)
    return host
end

Net.lan = require('source.katsa.net.lan')

-- True when the native library keeps ENet's unreliable-packet throttle off (see binding.lua).
function Net.unthrottled()
    return Binding.unthrottled()
end

function Net.shutdown()
    Binding.lib().knet_shutdown()
end

return Net
