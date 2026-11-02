-- Interface of the scene: the start menu (host, LAN list, join) and the in-game HUD.
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
        text = 'WASD move or drive, Space jump, Shift run or nitro, E enter / exit a car, N watch an ad for nitro',
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

-- In-game overlay: speed, nitro, seat and the buttons for changing car and watching an ad.
local Hud = {}
Hud.__index = Hud

local HUD_OFF = { 0.12, 0.2, 0.3 }

function Hud.create(scene, callbacks)
    local ui = scene.ui
    local self = setmetatable({ ui = ui }, Hud)
    self.root = ui:container({
        name = 'CarsHud',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        backgroundTransparency = 1,
    }, ui.content)
    self.info = ui:text({
        position = { 0, 16, 0, 62 },
        size = { 0.6, 0, 0, 56 },
        text = '',
        fontSize = 17,
        align = 'left',
    }, self.root)
    self.barBack = ui:container({
        position = { 0, 16, 1, -52 },
        size = { 0, 260, 0, 22 },
        backgroundColor = { 0.05, 0.07, 0.1 },
    }, self.root)
    self.bar = ui:container({
        position = { 0, 2, 0, 2 },
        size = { 1, -4, 1, -4 },
        backgroundColor = { 0.2, 0.75, 1 },
    }, self.barBack)
    ui:text({
        position = { 0, 16, 1, -80 },
        size = { 0, 260, 0, 22 },
        text = 'NITRO',
        fontSize = 14,
        align = 'left',
    }, self.root)
    self.speed = ui:text({
        position = { 1, -16, 1, -64 },
        size = { 0, 200, 0, 40 },
        anchorPoint = { 1, 0 },
        text = '0 km/h',
        fontSize = 28,
        align = 'right',
    }, self.root)
    self.sitButton = ui:button({
        position = { 1, -16, 0, 112 },
        size = { 0, 170, 0, 40 },
        anchorPoint = { 1, 0 },
        text = 'Enter car (E)',
        fontSize = 15,
        backgroundColor = { 0.085, 0.135, 0.19 },
        onPress = callbacks.sit,
    }, self.root)
    self.adButton = ui:button({
        position = { 1, -16, 0, 158 },
        size = { 0, 170, 0, 40 },
        anchorPoint = { 1, 0 },
        text = 'Nitro: watch ad (N)',
        fontSize = 15,
        backgroundColor = { 0.35, 0.2, 0.55 },
        onPress = callbacks.ad,
    }, self.root)
    ui:button({
        position = { 1, -16, 0, 204 },
        size = { 0, 170, 0, 40 },
        anchorPoint = { 1, 0 },
        text = 'Leave game',
        fontSize = 15,
        backgroundColor = { 0.4, 0.15, 0.15 },
        onPress = callbacks.leave,
    }, self.root)
    self.debugPath = ui:button({
        position = { 1, -16, 0, 250 },
        size = { 0, 170, 0, 40 },
        anchorPoint = { 1, 0 },
        text = 'Path debug: OFF',
        fontSize = 15,
        backgroundColor = { 0.1, 0.25, 0.2 },
        onPress = callbacks.pathDebug,
    }, self.root)
    -- Touch jump for the on-foot player; hidden while riding.
    self.jumpButton = ui:button({
        position = { 1, -16, 1, -150 },
        size = { 0, 120, 0, 64 },
        anchorPoint = { 1, 0 },
        text = 'Jump',
        fontSize = 20,
        backgroundColor = { 0.12, 0.3, 0.45 },
        onPress = callbacks.jump,
    }, self.root)
    -- Toggle buttons: tap once to keep running / crouching, tap again to stop.
    self.runButton = ui:button({
        position = { 1, -16, 1, -222 },
        size = { 0, 120, 0, 56 },
        anchorPoint = { 1, 0 },
        text = 'Run: OFF',
        fontSize = 18,
        backgroundColor = HUD_OFF,
        onPress = callbacks.run,
    }, self.root)
    self.crouchButton = ui:button({
        position = { 1, -146, 1, -150 },
        size = { 0, 120, 0, 64 },
        anchorPoint = { 1, 0 },
        text = 'Crouch: OFF',
        fontSize = 18,
        backgroundColor = HUD_OFF,
        onPress = callbacks.crouch,
    }, self.root)
    self.zoomIn = ui:button({
        position = { 0, 16, 1, -150 },
        size = { 0, 56, 0, 56 },
        text = '+',
        fontSize = 28,
        backgroundColor = HUD_OFF,
        onPress = function()
            callbacks.zoom(2)
        end,
    }, self.root)
    self.zoomOut = ui:button({
        position = { 0, 16, 1, -86 },
        size = { 0, 56, 0, 56 },
        text = '-',
        fontSize = 28,
        backgroundColor = HUD_OFF,
        onPress = function()
            callbacks.zoom(-2)
        end,
    }, self.root)
    -- Gives the cursor back (Tab does the same): the camera follows the mouse until then.
    self.menuButton = ui:button({
        position = { 1, -16, 1, -16 },
        size = { 0, 150, 0, 48 },
        anchorPoint = { 1, 1 },
        text = 'Menu (Tab)',
        fontSize = 18,
        backgroundColor = { 0.08, 0.16, 0.25 },
        onPress = callbacks.menu,
    }, self.root)
    self.message = ui:text({
        position = { 0.5, 0, 0, 120 },
        size = { 0, 500, 0, 30 },
        anchorPoint = { 0.5, 0 },
        text = '',
        fontSize = 18,
        textColor = { 1, 0.85, 0.4 },
    }, self.root)
    return self
end

function Hud:setPathDebug(on)
    self.debugPath.text = 'Path debug: ' .. (on and 'ON' or 'OFF')
end

-- On foot the seat button enters a car and Jump is shown; in a car it exits and nitro is shown.
function Hud:setOnFoot(onFoot)
    self.sitButton.text = onFoot and 'Enter car (E)' or 'Exit car (E)'
    self.jumpButton.visible = onFoot
    self.runButton.visible = onFoot
    self.crouchButton.visible = onFoot
    self.adButton.visible = not onFoot
end

local HUD_ON = { 0.15, 0.5, 0.25 }

function Hud:setToggles(run, crouch)
    self.runButton.text = 'Run: ' .. (run and 'ON' or 'OFF')
    self.runButton.backgroundColor = run and HUD_ON or HUD_OFF
    self.crouchButton.text = 'Crouch: ' .. (crouch and 'ON' or 'OFF')
    self.crouchButton.backgroundColor = crouch and HUD_ON or HUD_OFF
end

function Hud:setMenuOpen(open)
    self.menuButton.text = open and 'Resume (Tab)' or 'Menu (Tab)'
end

function Hud:setVisible(visible)
    self.root.visible = visible
end

function Hud:flash(text)
    self.message.text = text
    self.flashTime = 3
end

function Hud:update(dt, state)
    self.info.text = state.info or ''
    self.speed.text = ('%d km/h'):format(math.abs(state.speed or 0) * 3.6)
    self.bar.size = { math.max(0, math.min(1, state.nitro or 0)), -4, 1, -4 }
    self.adButton.text = state.adText or 'Nitro: watch ad (N)'
    if self.flashTime then
        self.flashTime = self.flashTime - dt
        if self.flashTime <= 0 then
            self.message.text, self.flashTime = '', nil
        end
    end
end

return { Menu = Menu, Hud = Hud }
