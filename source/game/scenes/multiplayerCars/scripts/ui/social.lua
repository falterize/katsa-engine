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

-- callbacks: send(text), kick(playerId)
function Social.create(scene, callbacks)
    local ui = scene.ui
    local self = setmetatable({ ui = ui, callbacks = callbacks, lines = {}, open = false }, Social)
    self.root = ui:container({
        name = 'CarsSocial',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        backgroundTransparency = 1,
        interactable = false, -- the root never blocks the game; its children opt in
    }, ui.content)
    self.chat = styled(ui, ui:container({
        name = 'ChatPanel',
        position = { 0, 16, 1, -330 },
        size = { 0, 380, 0, 180 },
        backgroundColor = PANEL,
        backgroundTransparency = 0.25,
        interactable = false,
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
        size = { 0, 380, 0, 300 },
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
    self.list = ui:scroll({
        position = { 0, 12, 0, 48 },
        size = { 1, -24, 1, -60 },
        length = 0,
    }, self.players)
    return self
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

function Social:isTyping()
    return self.typing == true
end

-- players: array of { id, name }; hostId; myId. Only the host gets Kick buttons.
function Social:setPlayers(players, hostId, myId)
    local ui = self.ui
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
            size = { 1, -110, 0, 34 },
            text = player.name .. tags,
            fontSize = 17,
            align = 'left',
            textColor = player.id == hostId and { 1, 0.8, 0.3 } or { 1, 1, 1 },
        }, self.list)
        if myId == hostId and player.id ~= myId then
            ui:button({
                position = { 1, -96, 0, y },
                size = { 0, 90, 0, 34 },
                text = 'Kick',
                fontSize = 15,
                backgroundColor = { 0.5, 0.15, 0.15 },
                onPress = function()
                    self.callbacks.kick(player.id)
                end,
            }, self.list)
        end
    end
    self.list.length = #players * 40
end

return Social
