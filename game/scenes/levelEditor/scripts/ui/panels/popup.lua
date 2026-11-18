-- One pop-up list used by the menu bar, the Create menu (Shift+A / the + button) and every
-- right-click menu. Items: { label, run, shortcut, checked, enabled } | { separator = true } |
-- { heading = text }. Long lists scroll; `search = true` adds a filter field (Enter runs the
-- first match). A click anywhere outside, or Esc, closes it.
local Focus = require('source.engine.ui.widgets.textFocus')
local Icons = require('../widgets.icons')
local Kit = require('../support.kit')

local Popup = {}
Popup.__index = Popup

local ITEM, SEPARATOR, SEARCH = 22, 7, 30

function Popup.create(state, ui)
    return setmetatable({ state = state, ui = ui, wasDown = false, wasEscape = false, rows = {} }, Popup)
end

function Popup:isOpen()
    return self.window ~= nil
end

function Popup:close()
    if self.window and not self.window.destroyed then
        if self.search and Focus.current == self.search then
            self.search:blur()
        end
        self.window:destroy()
    end
    self.window, self.search, self.scroll, self.rows = nil, nil, nil, {}
    local callback = self.onClose
    self.onClose = nil
    if callback then
        callback()
    end
end

local function shown(items, filter)
    if filter == '' then
        return items
    end
    local result = {}
    for _, entry in ipairs(items) do
        if entry.label and entry.label:lower():find(filter, 1, true) then
            result[#result + 1] = entry
        end
    end
    return result
end

function Popup:run(entry)
    self:close()
    local ok, message = pcall(entry.run)
    if not ok then
        self.state:notify(tostring(message))
    end
end

function Popup:fill(filter)
    for _, widget in ipairs(self.rows) do
        if not widget.destroyed then
            widget:destroy()
        end
    end
    self.rows = {}
    local ui, y = self.ui, 0
    local list = shown(self.items, filter)
    self.visible = list
    for _, entry in ipairs(list) do
        if entry.separator then
            self.rows[#self.rows + 1] = Kit.make(ui, 'Frame', {
                position = { 0, 8, 0, y + 3 },
                size = { 1, -16, 0, 1 },
                interactable = false,
            }, self.scroll, 'sep')
            y = y + SEPARATOR
        elseif entry.heading then
            self.rows[#self.rows + 1] = Kit.label(ui, self.scroll, entry.heading, {
                position = { 0, 10, 0, y },
                size = { 1, -20, 0, ITEM },
            }, 'muted')
            y = y + ITEM
        else
            local enabled = entry.enabled ~= false
            local mark = entry.checked ~= nil and (entry.checked and '[x]  ' or '[   ]  ') or ''
            local row = Kit.make(ui, 'Button', {
                position = { 0, 0, 0, y },
                size = { 1, 0, 0, ITEM },
                text = (entry.icon and '       ' or '') .. mark .. entry.label,
                align = 'left',
                fontSize = 13,
            }, self.scroll, 'row', enabled and nil or 'disabled')
            self.rows[#self.rows + 1] = row
            if entry.icon then
                Icons.add(ui, row, entry.icon, 6, (ITEM - 16) / 2)
            end
            if enabled then
                row:connect('press', function()
                    self:run(entry)
                end)
            end
            if entry.shortcut and entry.shortcut ~= '' then
                self.rows[#self.rows + 1] = Kit.label(ui, self.scroll, entry.shortcut, {
                    position = { 1, -100, 0, y },
                    size = { 0, 92, 0, ITEM },
                    align = 'right',
                    fontSize = 12,
                }, 'muted')
            end
            y = y + ITEM
        end
    end
    local top = self.search and SEARCH or 3
    local height = math.min(y + top + 6, self.ui.height - 16)
    self.scroll.position = { 0, 3, 0, top }
    self.scroll.size = { 1, -6, 0, height - top - 3 }
    self.scroll.canvasSize = { 0, 0, 0, y }
    self.window.size = { 0, self.width, 0, height }
    local px = math.max(2, math.min(self.x, self.ui.width - self.width - 2))
    local py = math.max(2, math.min(self.y, self.ui.height - height - 2))
    self.window.position = { 0, px, 0, py }
    self.state.styler:apply(self.window)
end

-- opts: width, search, ignore(mx, my) -> true when a press there must not close the list,
-- onClose().
function Popup:show(items, x, y, opts)
    self:close()
    opts = opts or {}
    self.items, self.x, self.y = items, x, y
    self.width, self.ignore, self.onClose = opts.width or 250, opts.ignore, opts.onClose
    local ui = self.ui
    self.window = Kit.make(ui, 'Frame', {
        name = 'Popup',
        position = { 0, x, 0, y },
        size = { 0, self.width, 0, 40 },
        zIndex = 40,
    }, ui.content, 'window')
    if opts.search then
        self.search = Kit.make(ui, 'TextBox', {
            position = { 0, 6, 0, 4 },
            size = { 1, -12, 0, 24 },
            fontSize = 13,
            text = '',
            placeholderText = 'Search...',
        }, self.window, 'field')
        self.search:connect('textChanged', function(_, text)
            self:fill((text or ''):lower())
        end)
        self.search:connect('submitted', function()
            for _, entry in ipairs(self.visible or {}) do
                if entry.run and entry.enabled ~= false then
                    self:run(entry)
                    return
                end
            end
        end)
    end
    self.scroll = Kit.make(ui, 'ScrollFrame', {
        size = { 1, -6, 1, -6 },
        canvasSize = { 0, 0, 0, 0 },
        scrollBarThickness = 5,
    }, self.window, 'popupList')
    self:fill('')
    if self.search then
        self.search:focus(true)
    end
    self.wasDown = true -- the press that opened the list must not close it
end

local function inside(node, mx, my)
    local x, y = node:getAbsolutePosition()
    local w, h = node:getAbsoluteSize()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function Popup:update()
    local down = katsa.mouse.isDown(1) or katsa.mouse.isDown(2)
    local escape = katsa.keyboard.isDown('escape')
    if self.window then
        local ui = self.ui
        local mx, my = (katsa.mouse.getX() - ui.offsetX) / ui.scale, (katsa.mouse.getY() - ui.offsetY) / ui.scale
        if down and not self.wasDown and not inside(self.window, mx, my) and not (self.ignore and self.ignore(mx, my)) then
            self:close()
        elseif escape and not self.wasEscape then
            self:close()
        end
    end
    self.wasDown, self.wasEscape = down, escape
end

return Popup
