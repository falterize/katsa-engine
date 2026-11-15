-- Chat: a remote event both ways. The server validates what clients send (length, rate) and
-- adds the nickname itself, so nobody can speak under another name.
local Chat = {}
Chat.__index = Chat

local MAX_LENGTH, MIN_INTERVAL = 120, 0.4

function Chat.new(server, nicknameOf)
    local self = setmetatable({ server = server, last = {} }, Chat)
    self.remote = server:remote('Chat')
    self.remote:onServer(function(player, text)
        if type(text) ~= 'string' then
            return
        end
        text = text:gsub('[%c]', ''):sub(1, MAX_LENGTH)
        local now = server.time
        if text == '' or now - (self.last[player.id] or -1) < MIN_INTERVAL then
            return
        end
        self.last[player.id] = now
        self.remote:fireAll(nicknameOf(player), text)
    end)
    return self
end

-- A line from the server itself.
function Chat:say(text)
    self.remote:fireAll('Server', text)
end

return Chat
