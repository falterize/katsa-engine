-- UI controller: chat, speaking indicator and the player list (Tab).
-- Chat and the player list. Chat lines fade after a few seconds unless the menu is open; Enter
-- opens the input box (and frees the cursor), Tab shows the player list, where the host can kick.
local Social = {}
Social.__index = Social

local PANEL = { 0.04, 0.07, 0.11 }
local STROKE = { 0.25, 0.5, 0.75 }
local VISIBLE_SECONDS, MAX_LINES = 10, 8

local function styled(ui, node, radius)
    ui:create('UICorner', { radius = { 0, radius or 10 } }, node)
    ui:create('UIStroke', { target = 'Border', thickness = { 0, 1.5 }, color = STROKE }, node)
    return node
end

-- callbacks: send(text), kick(playerId), hostCommand(name)
function Social.create(scene, callbacks)
    local ui = scene.ui
    local self = setmetatable({ ui = ui, callbacks = callbacks, lines = {}, open = false }, Social)
    self.root = ui:container({
        name = 'CarsSocial',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        backgroundTransparency = 1,
    }, ui.content)
    self.chat = styled(ui, ui:container({
        name = 'ChatPanel',
        position = { 0, 16, 1, -330 },
        size = { 0, 380, 0, 180 },
        backgroundColor = PANEL,
        backgroundTransparency = 0.25,
    }, self.root))
    self.log = ui:text({
        position = { 0, 12, 0, 8 },
        size = { 1, -24, 1, -16 },
        text = '',
        fontSize = 15,
        align = 'left',
        verticalAlign = 'bottom',
        interactable = false,
    }, self.chat)
    self.input = ui:create('TextBox', {
        name = 'ChatInput',
        position = { 0, 16, 1, -140 },
        size = { 0, 380, 0, 36 },
        text = '',
        placeholderText = 'Say something... (Enter to send, Esc to cancel)',
        fontSize = 15,
        backgroundColor = { 0.085, 0.135, 0.19 },
        visible = false,
        onSubmit = function(_, text)
            if text ~= '' then
                callbacks.send(text)
            end
        end,
        onFocusLost = function()
            self.input.text = ''
            self:setTyping(false)
        end,
    }, self.root)
    ui:create('UICorner', { radius = { 0, 8 } }, self.input)

    self.players = styled(ui, ui:container({
        name = 'PlayersPanel',
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 380, 0, 410 },
        anchorPoint = { 0.5, 0.5 },
        backgroundColor = PANEL,
        backgroundTransparency = 0.1,
        visible = false,
    }, self.root), 14)
    ui:text({
        position = { 0, 16, 0, 10 },
        size = { 1, -32, 0, 30 },
        text = 'Players',
        fontSize = 22,
        align = 'left',
    }, self.players)
    self.mic = ui:text({
        position = { 0, 16, 1, -26 },
        size = { 1, -32, 0, 20 },
        text = '',
        fontSize = 13,
        align = 'left',
        textColor = { 0.6, 0.75, 0.9 },
    }, self.players)
    self.list = ui:scroll({
        position = { 0, 12, 0, 48 },
        size = { 1, -24, 1, -196 },
        length = 0,
    }, self.players)
    -- Host tools: shown to the host only (the server checks again).
    self.hostTools = ui:container({
        position = { 0, 12, 1, -142 },
        size = { 1, -24, 0, 60 },
        backgroundTransparency = 1,
        visible = false,
    }, self.players)
    local tools = {
        { 'Spawn car', 'spawnCar' },
        { 'Spawn bot', 'spawnBot' },
        { 'Clear bots', 'clearBots' },
        { 'Clear cars', 'clearCars' },
    }
    for index, tool in ipairs(tools) do
        do
            local node = ui:button({
                position = { (index - 1) / 4, (index > 1 and 2 or 0), 0, 0 },
                size = { 0.25, -4, 1, 0 },
                text = tool[1],
                fontSize = 14,
                backgroundColor = index > 2 and { 0.5, 0.2, 0.15 } or { 0.1, 0.32, 0.45 },
            }, self.hostTools)
            node:connect('press', function()
                callbacks.hostCommand(tool[2])
            end)
        end
    end
    -- Network simulation: the player's own connection, and (hosting) the whole server.
    self.net = ui:container({
        position = { 0, 12, 1, -80 },
        size = { 1, -24, 0, 44 },
        backgroundTransparency = 1,
    }, self.players)
    self.netClient = ui:button({
        position = { 0, 0, 0, 0 },
        size = { 0.5, -4, 1, 0 },
        text = '',
        fontSize = 13,
        backgroundColor = { 0.2, 0.25, 0.3 },
    }, self.net)
    self.netClient:connect('press', function()
        callbacks.cycleClientNet()
    end)
    self.netServer = ui:button({
        position = { 0.5, 2, 0, 0 },
        size = { 0.5, -2, 1, 0 },
        text = '',
        fontSize = 13,
        backgroundColor = { 0.2, 0.25, 0.3 },
    }, self.net)
    self.netServer:connect('press', function()
        callbacks.cycleServerNet()
    end)
    return self
end

-- Labels of the network simulation buttons; serverLabel is nil when this process is no server.
function Social:setNetwork(clientLabel, serverLabel)
    self.netClient.text = 'My connection: ' .. clientLabel
    self.netServer.visible = serverLabel ~= nil
    self.netServer.text = 'Server: ' .. (serverLabel or '')
end

local function text(self)
    local shown, now = {}, os.clock()
    for index = math.max(1, #self.lines - MAX_LINES + 1), #self.lines do
        local line = self.lines[index]
        if self.open or now - line.time < VISIBLE_SECONDS then
            shown[#shown + 1] = line.text
        end
    end
    return table.concat(shown, '\n')
end

function Social:addLine(text_)
    self.lines[#self.lines + 1] = { text = text_, time = os.clock() }
    if #self.lines > 50 then
        table.remove(self.lines, 1)
    end
    self.log.text = text(self)
end

-- A chat message: `[HOST]` marks the host.
function Social:addChat(line)
    self:addLine(('%s%s: %s'):format(line.host and '[HOST] ' or '', line.name, line.text))
end

function Social:update()
    local shown = text(self)
    if shown ~= self.log.text then
        self.log.text = shown
    end
    self.chat.visible = shown ~= '' or self.open or self.typing == true
end

-- Voice meters, top-left: one row per audible speaker (you included) with a loudness bar.
-- meters: array of { name, level 0..1, mine }.
function Social:setSpeaking(meters)
    local ui = self.ui
    self.meterRows = self.meterRows or {}
    for index = 1, math.max(#meters, #self.meterRows) do
        local row = self.meterRows[index]
        local meter = meters[index]
        if meter and not row then
            row = { frame = ui:container({
                position = { 0, 16, 0, 130 + (index - 1) * 26 },
                size = { 0, 300, 0, 22 },
                backgroundColor = PANEL,
                backgroundTransparency = 0.3,
            }, self.root) }
            row.fill = ui:container({
                position = { 0, 2, 0, 2 },
                size = { 0, 0, 1, -4 },
                backgroundColor = { 0.3, 0.9, 0.5 },
            }, row.frame)
            row.name = ui:text({
                position = { 0, 6, 0, 0 },
                size = { 1, -12, 1, 0 },
                text = '',
                fontSize = 14,
                align = 'left',
            }, row.frame)
            ui:create('UICorner', { radius = { 0, 6 } }, row.frame)
            self.meterRows[index] = row
        end
        if row then
            row.frame.visible = meter ~= nil
            if meter then
                local text_ = meter.mine and 'You (mic)' or meter.name
                if row.name.text ~= text_ then
                    row.name.text = text_
                end
                row.fill.size = { 0, math.floor(296 * meter.level), 1, -4 }
                row.fill.backgroundColor = meter.level > 0.8 and { 1, 0.45, 0.3 } or { 0.3, 0.9, 0.5 }
            end
        end
    end
end

-- Menu open (cursor free): the full chat history and the player list are visible.
function Social:setMenuOpen(open)
    self.open = open
    self.players.visible = open
    self.log.text = text(self)
    self.chat.visible = open or self.log.text ~= ''
end

function Social:setTyping(typing)
    self.typing = typing
    self.input.visible = typing
    if typing then
        self.input:focus()
    elseif self.onTypingDone then
        self.onTypingDone()
    end
end

-- Microphone line of the player list: 'ready', or why there is none.
function Social:setMicStatus(text_)
    self.mic.text = text_ == 'ready' and 'Microphone: ready (hold V to talk)'
        or ('Microphone: ' .. tostring(text_))
end

function Social:isTyping()
    return self.typing == true
end

local function pingColor(ping)
    if not ping then
        return { 0.6, 0.6, 0.6 }
    elseif ping < 80 then
        return { 0.45, 0.9, 0.5 }
    elseif ping < 160 then
        return { 1, 0.85, 0.35 }
    end
    return { 1, 0.45, 0.4 }
end

-- players: array of { id, name, ping }; hostId; myId. Only the host gets Kick buttons.
function Social:setPlayers(players, hostId, myId)
    local ui = self.ui
    self.hostTools.visible = myId == hostId
    for index = #self.list.children, 1, -1 do
        self.list.children[index]:destroy()
    end
    table.sort(players, function(a, b)
        return a.id < b.id
    end)
    for index, player in ipairs(players) do
        local y = (index - 1) * 40
        local tags = (player.id == hostId and ' [HOST]' or '') .. (player.id == myId and ' (you)' or '')
        ui:text({
            position = { 0, 6, 0, y },
            size = { 1, -170, 0, 34 },
            text = player.name .. tags,
            fontSize = 17,
            align = 'left',
            textColor = player.id == hostId and { 1, 0.8, 0.3 } or { 1, 1, 1 },
        }, self.list)
        ui:text({
            position = { 1, -166, 0, y },
            size = { 0, 64, 0, 34 },
            text = player.ping and (math.floor(player.ping + 0.5) .. ' ms') or '-',
            fontSize = 15,
            align = 'right',
            textColor = pingColor(player.ping),
        }, self.list)
        if myId == hostId and player.id ~= myId then
            do
                local node = ui:button({
                    position = { 1, -96, 0, y },
                    size = { 0, 90, 0, 34 },
                    text = 'Kick',
                    fontSize = 15,
                    backgroundColor = { 0.5, 0.15, 0.15 },
                }, self.list)
                node:connect('press', function()
                    self.callbacks.kick(player.id)
                end)
            end
        end
    end
    self.list.length = #players * 40
end

return Social
