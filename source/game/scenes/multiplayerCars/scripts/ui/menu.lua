-- Start screen: host a game, pick a server from the LAN list or type an address.
local Menu = {}
Menu.__index = Menu

local PANEL = { 0.035, 0.065, 0.105 }
local BUTTON = { 0.085, 0.135, 0.19 }

-- callbacks: host(name), join(address, port, name)
function Menu.create(scene, callbacks)
    local ui = scene.ui
    local self = setmetatable({ ui = ui, callbacks = callbacks, rows = {} }, Menu)
    self.panel = ui:container({
        name = 'CarsMenu',
        position = { 0.5, 0, 0.5, 0 },
        anchorPoint = { 0.5, 0.5 },
        size = { 0, 560, 0, 520 },
        backgroundColor = PANEL,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, 14 } }, self.panel)
    ui:text({
        position = { 0, 20, 0, 12 },
        size = { 1, -40, 0, 36 },
        text = 'KATSA CARS / multiplayer',
        fontSize = 26,
        align = 'left',
    }, self.panel)
    ui:text({
        position = { 0, 20, 0, 50 },
        size = { 1, -40, 0, 22 },
        text = 'WASD / arrows drive, Shift nitro, E change car, N watch an ad for nitro',
        fontSize = 15,
        textColor = { 0.5, 0.75, 0.9 },
        align = 'left',
    }, self.panel)
    self.name = ui:create('TextBox', {
        position = { 0, 20, 0, 84 },
        size = { 0.5, -26, 0, 38 },
        text = 'Player',
        placeholderText = 'Your name',
        fontSize = 16,
        backgroundColor = BUTTON,
    }, self.panel)
    ui:button({
        position = { 0.5, 6, 0, 84 },
        size = { 0.5, -26, 0, 38 },
        text = 'Host a game',
        fontSize = 17,
        backgroundColor = { 0.12, 0.35, 0.22 },
        onPress = function()
            callbacks.host(self.name.text)
        end,
    }, self.panel)
    ui:text({
        position = { 0, 20, 0, 134 },
        size = { 1, -40, 0, 22 },
        text = 'Games on your network',
        fontSize = 15,
        align = 'left',
    }, self.panel)
    self.list = ui:scroll({
        position = { 0, 20, 0, 160 },
        size = { 1, -40, 0, 220 },
        length = 220,
        backgroundColor = { 0.025, 0.045, 0.075 },
    }, self.panel)
    self.empty = ui:text({
        position = { 0, 10, 0, 10 },
        size = { 1, -20, 0, 30 },
        text = 'Searching...',
        fontSize = 14,
        align = 'left',
    }, self.list)
    self.address = ui:create('TextBox', {
        position = { 0, 20, 0, 396 },
        size = { 0.5, -26, 0, 38 },
        text = '127.0.0.1:7777',
        placeholderText = 'address:port',
        fontSize = 16,
        backgroundColor = BUTTON,
    }, self.panel)
    ui:button({
        position = { 0.5, 6, 0, 396 },
        size = { 0.5, -26, 0, 38 },
        text = 'Join address',
        fontSize = 17,
        backgroundColor = BUTTON,
        onPress = function()
            local host, port = self.address.text:match('^%s*([^:%s]+):?(%d*)%s*$')
            if host then
                callbacks.join(host, tonumber(port) or 7777, self.name.text)
            end
        end,
    }, self.panel)
    self.status = ui:text({
        position = { 0, 20, 0, 448 },
        size = { 1, -40, 0, 50 },
        text = '',
        fontSize = 14,
        textColor = { 1, 0.8, 0.45 },
        align = 'left',
    }, self.panel)
    return self
end

function Menu:setStatus(text)
    self.status.text = text or ''
end

function Menu:setVisible(visible)
    self.panel.visible = visible
end

-- servers: entries from Net.browse():update()
function Menu:setServers(servers)
    local signature = {}
    for _, server in ipairs(servers) do
        signature[#signature + 1] = server.name .. server.address .. server.port .. server.players
    end
    signature = table.concat(signature, ';')
    if signature == self.signature then
        return
    end
    self.signature = signature
    for _, row in ipairs(self.rows) do
        row:destroy()
    end
    self.rows = {}
    self.empty.visible = #servers == 0
    self.empty.text = 'No games found. Host one or type an address.'
    for index, server in ipairs(servers) do
        self.rows[index] = self.ui:button({
            position = { 0, 8, 0, 8 + (index - 1) * 46 },
            size = { 1, -16, 0, 40 },
            text = ('%s  -  %d/%d  -  %s:%d'):format(
                server.name,
                server.players,
                server.maxPlayers,
                server.address,
                server.port
            ),
            fontSize = 15,
            backgroundColor = BUTTON,
            onPress = function()
                self.callbacks.join(server.address, server.port, self.name.text)
            end,
        }, self.list)
    end
    self.list.length = math.max(220, #servers * 46 + 16)
end

return Menu
