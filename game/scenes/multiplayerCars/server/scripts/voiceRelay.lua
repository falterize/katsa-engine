-- Server side of voice chat: relays each player's compressed audio packets to everybody else over
-- an unreliable remote, with a size limit and a per-player burst limit.
local VoiceRelay = {}

local MAX_PACKET = 2400

function VoiceRelay.bind(server)
    local remote = server.server:remote('voice'):unreliable()
    local last = {}
    remote:onServer(function(player, bytes)
        if type(bytes) ~= 'string' or #bytes == 0 or #bytes > MAX_PACKET then
            return
        end
        -- 80 ms of audio per packet; allow bursts but not floods.
        local now = server.server.time
        local gate = last[player.id] or { time = now, tokens = 8 }
        gate.tokens = math.min(8, gate.tokens + (now - gate.time) * 12.5)
        gate.time = now
        last[player.id] = gate
        if gate.tokens < 1 then
            return
        end
        gate.tokens = gate.tokens - 1
        remote:fireOthers(player, player.id, bytes)
    end)
end

return VoiceRelay
