-- Engine networking: authoritative Server and predicting Client over katsa.net.
-- See docs/guides/development/multiplayer.md.
local Net = {
    Server = require('source.engine.net.server'),
    Client = require('source.engine.net.client'),
    Link = require('source.engine.net.link'),
    Conditions = require('source.engine.net.conditions'),
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
            -- One server answers every query path (broadcast and loopback), from different
            -- source addresses. Collapse those replies into a single entry, preferring the
            -- network address over 127.0.0.1 so other machines can use it too.
            local byKey = {}
            for _, server in ipairs(browser:update()) do
                local name, port, players, maxPlayers, game =
                    server.info:match('^(.-)|(%d+)|(%d+)|(%d+)|(.*)$')
                if name then
                    local key = name .. '|' .. port .. '|' .. game
                    local known = byKey[key]
                    if not known then
                        known = { loopbackOnly = true }
                        byKey[key] = known
                        list[#list + 1] = known
                    end
                    local loopback = server.address:match('^127%.') ~= nil
                    if not loopback or known.address == nil then
                        known.name = name
                        known.address = server.address
                        known.port = tonumber(port)
                        known.players = tonumber(players)
                        known.maxPlayers = tonumber(maxPlayers)
                        known.game = game
                        known.loopbackOnly = loopback
                    end
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
