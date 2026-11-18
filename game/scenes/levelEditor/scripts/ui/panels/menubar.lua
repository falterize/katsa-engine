-- The menu bar: File, Edit, Create, View, Settings. A click opens the list (panels/popup) under
-- the title; while one is open, hovering another title switches to it.
local Pointer = require('../../input.pointer')
local Kit = require('../support.kit')
local Menus = require('../support.menus')

local Menubar = {}
Menubar.__index = Menubar

function Menubar.create(state, ui, parent)
    local self = setmetatable({ state = state, ui = ui, titles = {} }, Menubar)
    local x = 6
    for index, menu in ipairs(Menus.list) do
        local width = #menu.title * 8 + 22
        local button = Kit.button(ui, parent, menu.title, width, 24, function()
            if self.open == index then
                state.panels.popup:close()
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

local function inside(node, mx, my)
    local x, y, w, h = Kit.rect(node)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- Clears the highlight of every title. The style must be applied again or the old colour stays.
function Menubar:clearHighlight()
    self.open = nil
    for _, button in ipairs(self.titles) do
        button:removeTag('selected')
        self.state.styler:apply(button)
    end
end

function Menubar:openMenu(index)
    local state = self.state
    local button = self.titles[index]
    local bx, by = button:getAbsolutePosition()
    local _, bh = button:getAbsoluteSize()
    state.panels.popup:show(Menus.list[index].items(state), bx, by + bh + 1, {
        width = 250,
        ignore = function(mx, my)
            for _, title in ipairs(self.titles) do
                if inside(title, mx, my) then
                    return true
                end
            end
            return false
        end,
        onClose = function()
            self:clearHighlight()
        end,
    })
    -- show() closed the previous list (and cleared the highlight) first, so mark the new title now.
    self.open = index
    button:addTag('selected')
    state.styler:apply(button)
end

function Menubar:update()
    if not self.open then
        return
    end
    local ui = self.ui
    local mx, my = (Pointer.getX() - ui.offsetX) / ui.scale, (Pointer.getY() - ui.offsetY) / ui.scale
    for index, button in ipairs(self.titles) do
        if index ~= self.open and inside(button, mx, my) then
            self:openMenu(index)
            break
        end
    end
end

return Menubar
