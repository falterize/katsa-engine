-- Engine networking: authoritative Server and predicting Client over katsa.net.
-- See docs/guides/development/multiplayer.md.
local Net = {
    Server = require('source.engine.net.server'),
    Client = require('source.engine.net.client'),
    Link = require('source.engine.net.link'),
    Types = require('source.engine.net.types'),
    Codec = require('source.engine.net.codec'),
}

-- LAN server list. Returns a browser whose update() gives
-- { name, address, port, players, maxPlayers, game } entries.
function Net.browse(options)
    local browser = katsa.net.lan.browse(options)
    local list = {}
    return {
        -- Queries the LAN (broadcast), or one address such as '127.0.0.1' for this machine.
        refresh = function(address)
            browser:refresh(address)
        end,
        update = function()
            list = {}
            for _, server in ipairs(browser:update()) do
                local name, port, players, maxPlayers, game =
                    server.info:match('^(.-)|(%d+)|(%d+)|(%d+)|(.*)$')
                if name then
                    list[#list + 1] = {
                        name = name,
                        address = server.address,
                        port = tonumber(port),
                        players = tonumber(players),
                        maxPlayers = tonumber(maxPlayers),
                        game = game,
                    }
                end
            end
            return list
        end,
        close = function()
            browser:close()
        end,
    }
end

return Net
