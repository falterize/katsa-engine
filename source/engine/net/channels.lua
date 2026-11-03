-- Channel choice for the high-rate state packets (snapshots and client input).
local P = require('./protocol')

local Channels = {}

-- Unreliable sequenced when the native library keeps ENet's throttle off. A library built before
-- that fix drops most unreliable packets for the first seconds of a connection, so state is sent
-- reliably there (ordered, a little more latency under loss, but never silently dropped).
function Channels.state()
    if Channels.cached == nil then
        local net = katsa.net
        Channels.cached = (net.unthrottled == nil or net.unthrottled()) and P.SEQUENCED
            or P.RELIABLE
    end
    return Channels.cached
end

return Channels
