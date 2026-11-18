-- The menu bar: File, Edit, Create, View, Settings. A click opens a drop-down under the title;
-- while one is open, hovering another title switches to it; a click anywhere else closes it.
local Kit = require('../kit')
local Menus = require('../menus')

local Menubar = {}
Menubar.__index = Menubar

local ITEM, WIDTH, SEPARATOR_HEIGHT = 22, 250, 7

function Menubar.create(state, ui, parent)
    local self = setmetatable({ state = state, ui = ui, titles = {}, widgets = {}, wasDown = false }, Menubar)
    local x = 6
    for index, menu in ipairs(Menus.list) do
        local width = #menu.title * 8 + 22
        local button = Kit.button(ui, parent, menu.title, width, 24, function()
            if self.open == index then
                self:close()
            else
                self:openMenu(index)
            end
        end, 'tab')
        button.position = { 0, x, 0, 2 }
        self.titles[index] = button
        x = x + width + 2
    end
    return self
end

function Menubar:close()
    if self.popup and not self.popup.destroyed then
        self.popup:destroy()
    end
    self.popup, self.open = nil, nil
    for _, button in ipairs(self.titles) do
        button:removeTag('selected')
    end
end

function Menubar:openMenu(index)
    self:close()
    local state, ui = self.state, self.ui
    local items = Menus.list[index].items(state)
    local height = 6
    for _, entry in ipairs(items) do
        height = height + (entry.separator and SEPARATOR_HEIGHT or ITEM)
    end
    local button = self.titles[index]
    local bx, by = button:getAbsolutePosition()
    local _, bh = button:getAbsoluteSize()
    local x = math.max(2, math.min(bx, ui.width - WIDTH - 2))
    self.popup = Kit.make(ui, 'Frame', {
        name = 'Menu',
        position = { 0, x, 0, by + bh + 1 },
        size = { 0, WIDTH, 0, height },
        zIndex = 40,
    }, ui.content, 'window')
    local y = 3
    for _, entry in ipairs(items) do
        if entry.separator then
            Kit.make(ui, 'Frame', {
                position = { 0, 8, 0, y + 3 },
                size = { 1, -16, 0, 1 },
                interactable = false,
            }, self.popup, 'sep')
            y = y + SEPARATOR_HEIGHT
        elseif entry.heading then
            Kit.label(ui, self.popup, entry.heading, { position = { 0, 10, 0, y }, size = { 1, -20, 0, ITEM } }, 'muted')
            y = y + ITEM
        else
            local enabled = entry.enabled ~= false
            local label = (entry.checked ~= nil and (entry.checked and '[x]  ' or '[   ]  ') or '') .. entry.label
            local row = Kit.make(ui, 'Button', {
                position = { 0, 3, 0, y },
                size = { 1, -6, 0, ITEM },
                text = label,
                align = 'left',
                fontSize = 13,
            }, self.popup, 'row', enabled and nil or 'disabled')
            if enabled then
                row:connect('press', function()
                    self:close()
                    local ok, message = pcall(entry.run)
                    if not ok then
                        state:notify(tostring(message))
                    end
                end)
            end
            if entry.shortcut and entry.shortcut ~= '' then
                Kit.label(ui, self.popup, entry.shortcut, {
                    position = { 1, -100, 0, y },
                    size = { 0, 92, 0, ITEM },
                    align = 'right',
                    fontSize = 12,
                }, 'muted')
            end
            y = y + ITEM
        end
    end
    self.open = index
    self.titles[index]:addTag('selected')
    state.styler:apply(self.popup)
    state.styler:apply(self.titles[index])
end

local function inside(node, mx, my)
    local x, y = node:getAbsolutePosition()
    local w, h = node:getAbsoluteSize()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function Menubar:update()
    local ui = self.ui
    local down = katsa.mouse.isDown(1)
    if self.open then
        local mx, my = (katsa.mouse.getX() - ui.offsetX) / ui.scale, (katsa.mouse.getY() - ui.offsetY) / ui.scale
        for index, button in ipairs(self.titles) do
            if index ~= self.open and inside(button, mx, my) then
                self:openMenu(index)
                break
            end
        end
        -- A fresh press outside both the open menu and the titles closes it.
        if down and not self.wasDown and self.popup then
            local onTitle = false
            for _, button in ipairs(self.titles) do
                onTitle = onTitle or inside(button, mx, my)
            end
            if not onTitle and not inside(self.popup, mx, my) then
                self:close()
            end
        end
    end
    self.wasDown = down
end

return Menubar
