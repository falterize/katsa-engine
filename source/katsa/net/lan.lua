-- LAN server discovery over UDP broadcast. A server runs an Announcer that answers queries with
-- an opaque info string; a client runs a Browser that broadcasts a query and collects replies.
local ffi = require('ffi')
local Binding = require('source.katsa.net.binding')

local Lan = {}

local QUERY, REPLY = 'KATSA?', 'KATSA!'
local MAX = 1200

local function receive(socket)
    local lib = Binding.lib()
    local data, ip, port = ffi.new('char[?]', MAX), ffi.new('char[64]'), ffi.new('int[1]')
    return function()
        local size = lib.knet_lan_receive(socket, data, MAX, ip, 64, port)
        if size > 0 then
            return ffi.string(data, size), ffi.string(ip), port[0]
        end
    end
end

local Announcer = {}
Announcer.__index = Announcer

-- port: the discovery port (default 7776). info: string describing the server (name, game port...).
function Lan.announce(options)
    local socket = Binding.lib().knet_lan_open(options.port or 7776)
    assert(socket >= 0, 'Could not open the LAN discovery port')
    return setmetatable({ socket = socket, info = options.info or '' }, Announcer)
end

function Announcer:setInfo(info)
    self.info = info
end

function Announcer:update()
    for data, ip, port in receive(self.socket) do
        if data == QUERY then
            local reply = REPLY .. self.info
            Binding.lib().knet_lan_send(self.socket, ip, port, reply, #reply)
        end
    end
end

function Announcer:close()
    if self.socket then
        Binding.lib().knet_lan_close(self.socket)
        self.socket = nil
    end
end

local Browser = {}
Browser.__index = Browser

function Lan.browse(options)
    options = options or {}
    local socket = Binding.lib().knet_lan_open(0)
    assert(socket >= 0, 'Could not open a LAN socket')
    return setmetatable({
        socket = socket,
        port = options.port or 7776,
        timeout = options.timeout or 5,
        servers = {},
    }, Browser)
end

-- Broadcast a query. Replies arrive during update().
function Browser:refresh(address)
    Binding.lib().knet_lan_send(self.socket, address, self.port, QUERY, #QUERY)
end

-- Collects replies; returns { address, port, info, seen } entries sorted by address.
function Browser:update(now)
    now = now or os.clock()
    for data, ip, port in receive(self.socket) do
        if data:sub(1, #REPLY) == REPLY then
            self.servers[ip .. ':' .. port] = {
                address = ip,
                port = port,
                info = data:sub(#REPLY + 1),
                seen = now,
            }
        end
    end
    local list = {}
    for key, server in pairs(self.servers) do
        if now - server.seen > self.timeout then
            self.servers[key] = nil
        else
            list[#list + 1] = server
        end
    end
    table.sort(list, function(a, b)
        return a.address == b.address and a.port < b.port or a.address < b.address
    end)
    return list
end

function Browser:close()
    if self.socket then
        Binding.lib().knet_lan_close(self.socket)
        self.socket = nil
    end
end

return Lan
