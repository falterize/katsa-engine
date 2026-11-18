-- Hover descriptions. Widgets register a node with a text (or a function returning one); after
-- the pointer rests on a registered widget for a moment a small window with the text appears next
-- to it and follows nothing: it hides when the pointer leaves, a press happens or a pop-up opens.
-- Destroyed widgets are dropped from the registry on the way.
local Pointer = require('../../input.pointer')
local Kit = require('../support.kit')

local Tooltip = {}
Tooltip.__index = Tooltip

local DELAY, WIDTH, LINE, MAX_LINES = 0.45, 280, 16, 6

function Tooltip.create(state, ui)
    return setmetatable({ state = state, ui = ui, entries = {}, hovered = nil, since = 0 }, Tooltip)
end

-- `text` is a string or a function returning one (evaluated when the tip opens).
function Tooltip:register(node, text)
    if text and text ~= '' then
        self.entries[#self.entries + 1] = { node = node, text = text }
    end
end

function Tooltip:hide()
    if self.window and not self.window.destroyed then
        self.window:destroy()
    end
    self.window, self.label, self.shown = nil, nil, nil
end

local function over(node, mx, my)
    local x, y, w, h = Kit.rect(node)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- Rough word wrap: the label wraps by itself, so only the window height needs an estimate.
local function lines(text)
    return math.min(MAX_LINES, math.max(1, math.ceil(#text * 6.4 / (WIDTH - 16))))
end

function Tooltip:show(entry, mx, my)
    local text = entry.text
    if type(text) == 'function' then
        text = text()
    end
    if type(text) ~= 'string' or text == '' then
        return
    end
    local ui = self.ui
    local height = lines(text) * LINE + 12
    local x = math.max(2, math.min(mx + 14, ui.width - WIDTH - 2))
    local y = my + 22
    if y + height > ui.height - 2 then
        y = my - height - 8
    end
    self.window = Kit.make(ui, 'Frame', {
        name = 'Tooltip',
        position = { 0, x, 0, y },
        size = { 0, WIDTH, 0, height },
        zIndex = 60,
        interactable = false,
    }, ui.content, 'window')
    self.label = Kit.label(ui, self.window, text, {
        position = { 0, 8, 0, 6 },
        size = { 1, -16, 1, -12 },
        fontSize = 12,
    }, 'text')
    self.state.styler:apply(self.window)
    self.shown = entry
end

function Tooltip:update()
    local now = katsa.timer.getTime()
    local dt = math.min(0.1, now - (self.last or now))
    self.last = now
    local ui, state = self.ui, self.state
    local mx, my = (Pointer.getX() - ui.offsetX) / ui.scale, (Pointer.getY() - ui.offsetY) / ui.scale
    local pressed = Pointer.isDown(1) or Pointer.isDown(2)
    local popup = state.panels.popup
    local blocked = pressed or (popup and popup:isOpen()) or (state.panels.colorPicker and state.panels.colorPicker:isOpen())
    -- Hit-testing every registered widget costs real time; do it when the pointer moved, and
    -- otherwise only now and then (a panel may have changed under a resting pointer).
    self.frame = (self.frame or 0) + 1
    local found = self.found
    if mx ~= self.lastX or my ~= self.lastY or blocked ~= self.lastBlocked or self.frame % 15 == 0 then
        self.lastX, self.lastY, self.lastBlocked = mx, my, blocked
        found = nil
        local kept = {}
        for _, entry in ipairs(self.entries) do
            local node = entry.node
            if not node.destroyed then
                kept[#kept + 1] = entry
                if not found and not blocked and node.visible ~= false and over(node, mx, my) then
                    found = entry
                end
            end
        end
        self.entries = kept
        self.found = found
    end
    if found ~= self.hovered then
        self.hovered, self.since = found, 0
        self:hide()
    elseif found then
        self.since = self.since + dt
        if self.since >= DELAY and not self.window then
            self:show(found, mx, my)
        end
    end
    if blocked and self.window then
        self:hide()
    end
end

return Tooltip
