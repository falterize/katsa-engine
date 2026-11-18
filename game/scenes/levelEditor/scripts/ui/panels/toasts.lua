-- On-screen notifications (like the Unity editor's): a short card in the top-right corner of the
-- window for every message and error, fading after a few seconds. The same lines also go to the
-- Console tab of the bottom dock, so nothing is lost once a card is gone.
local Kit = require('../support.kit')

local Toasts = {}
Toasts.__index = Toasts

local WIDTH, HEIGHT, GAP, TOP = 340, 40, 6, 36
local LIMIT = 5
local LIFE = { info = 4, warn = 6, error = 8 }

function Toasts.create(state, ui)
    return setmetatable({ state = state, ui = ui, cards = {} }, Toasts)
end

function Toasts:push(text, level)
    local ui = self.ui
    local card = Kit.make(ui, 'Frame', {
        size = { 0, WIDTH, 0, HEIGHT },
        zIndex = 60,
        interactable = false,
    }, ui.content, 'window')
    Kit.label(ui, card, text, {
        position = { 0, 10, 0, 4 },
        size = { 1, -20, 1, -8 },
        fontSize = 13,
        textScaled = true,
        minTextSize = 9,
        maxTextSize = 13,
        verticalAlign = 'center',
    }, level == 'info' and 'text' or level)
    self.state.styler:apply(card)
    table.insert(self.cards, 1, { node = card, left = LIFE[level] or LIFE.info })
    while #self.cards > LIMIT do
        local old = table.remove(self.cards)
        old.node:destroy()
    end
    self:place()
end

-- Newest card on top; the column hangs from the right edge of the window.
function Toasts:place()
    for index, card in ipairs(self.cards) do
        card.node.position = { 1, -(WIDTH + 12), 0, TOP + (index - 1) * (HEIGHT + GAP) }
    end
end

function Toasts:update()
    local now = katsa.timer.getTime()
    local dt = math.min(0.25, now - (self.last or now))
    self.last = now
    local changed = false
    for index = #self.cards, 1, -1 do
        local card = self.cards[index]
        card.left = card.left - dt
        if card.left <= 0 then
            card.node:destroy()
            table.remove(self.cards, index)
            changed = true
        end
    end
    if changed then
        self:place()
    end
end

return Toasts
