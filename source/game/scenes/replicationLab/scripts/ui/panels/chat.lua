-- Chat panel: the last lines, and a box that opens with Enter. A line goes to the server, which
-- checks it, adds the nickname and sends it to everybody.
local Chat = {}
Chat.__index = Chat

local MAX_LINES = 8

-- callbacks: send(text), typing(isTyping)
function Chat.create(ui, callbacks)
    local self = setmetatable({ lines = {}, callbacks = callbacks }, Chat)
    self.log = ui:text({
        name = 'ChatLog',
        position = { 0, 16, 1, -120 },
        size = { 0, 420, 0, 170 },
        anchorPoint = { 0, 1 },
        text = '',
        fontSize = 16,
        align = 'left',
        verticalAlign = 'bottom',
        interactable = false,
    }, ui.content)
    self.input = ui:create('TextBox', {
        name = 'ChatInput',
        position = { 0, 16, 1, -70 },
        size = { 0, 420, 0, 36 },
        anchorPoint = { 0, 1 },
        text = '',
        placeholderText = 'Say something (Enter sends, Esc cancels)',
        fontSize = 16,
        backgroundColor = { 0.085, 0.135, 0.19 },
        visible = false,
    }, ui.content)
    self.input:connect('submitted', function(_, text)
        if text ~= '' then
            callbacks.send(text)
        end
    end)
    self.input:connect('focusLost', function()
        self.input.text = ''
        self.input.visible = false
        self.typing = false
        callbacks.typing(false)
    end)
    return self
end

function Chat:add(author, text)
    self.lines[#self.lines + 1] = author .. ': ' .. text
    if #self.lines > MAX_LINES then
        table.remove(self.lines, 1)
    end
    self.log.text = table.concat(self.lines, '\n')
end

function Chat:open()
    if not self.typing then
        self.typing = true
        self.input.visible = true
        self.input:focus()
        self.callbacks.typing(true)
    end
end

return Chat
