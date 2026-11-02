-- Named remote events and functions. A Remote belongs to a Server or a Client (`owner`) and
-- sends through it. Handlers receive the arguments the other side passed; on the server the
-- first handler argument is the Player that sent it.
local Remote = {}
Remote.__index = Remote

function Remote.new(owner, name)
    return setmetatable({ owner = owner, name = name }, Remote)
end

-- Marks the remote as best-effort (no retransmission, may be dropped or reordered): for streams
-- such as voice where an old packet is worthless.
function Remote:unreliable()
    self.channel = 3 -- Protocol.UNRELIABLE
    return self
end

-- Server side
function Remote:onServer(handler)
    self.serverHandler = handler
    return self
end

function Remote:fireClient(player, ...)
    self.owner:sendRemote(player, self.name, select('#', ...), { ... })
end

function Remote:fireAll(...)
    for _, player in pairs(self.owner.players) do
        self.owner:sendRemote(player, self.name, select('#', ...), { ... })
    end
end

function Remote:fireOthers(except, ...)
    for _, player in pairs(self.owner.players) do
        if player ~= except then
            self.owner:sendRemote(player, self.name, select('#', ...), { ... })
        end
    end
end

-- Handler returns values; the client's request callback receives them.
function Remote:onRequest(handler)
    self.requestHandler = handler
    return self
end

-- Client side
function Remote:onClient(handler)
    self.clientHandler = handler
    return self
end

function Remote:fireServer(...)
    self.owner:sendRemote(nil, self.name, select('#', ...), { ... })
end

-- request(callback, ...): asks the server's onRequest handler; callback(...) gets the answer.
function Remote:request(callback, ...)
    self.owner:sendRequest(self.name, callback, select('#', ...), { ... })
end

return Remote
