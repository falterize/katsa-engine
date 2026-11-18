-- Places the editor frames from the pure Layout rectangles and runs the three splitters. The
-- frames are only touched when the window, a splitter or the toolbar height changed.
local Layout = require('./layout')

local Dock = {}
Dock.__index = Dock

Dock.STATUS = 24

-- frames: { top, left, right, bottom, status, splitLeft, splitRight, splitBottom }
function Dock.new(state, ui, frames, sizes)
    local self = setmetatable({ state = state, ui = ui, frames = frames, drag = nil }, Dock)
    self.preferred = { left = sizes.left, right = sizes.right, bottom = sizes.bottom }
    self.key = nil
    for name in pairs({ splitLeft = true, splitRight = true, splitBottom = true }) do
        frames[name]:connect('press', function()
            local x, y = katsa.mouse.getX(), katsa.mouse.getY()
            self.drag = {
                name = name,
                x = (x - ui.offsetX) / ui.scale,
                y = (y - ui.offsetY) / ui.scale,
                sizes = { left = self.current.left, right = self.current.right, bottom = self.current.bottom },
            }
        end)
    end
    return self
end

-- The sizes to save: what the user chose, not what a small window forced.
function Dock:sizes()
    return { left = self.preferred.left, right = self.preferred.right, bottom = self.preferred.bottom }
end

function Dock:setSizes(sizes)
    for key in pairs(self.preferred) do
        self.preferred[key] = sizes[key] or self.preferred[key]
    end
    self.key = nil
end

local function place(frame, rect)
    frame.position = { 0, rect.x, 0, rect.y }
    frame.size = { 0, rect.w, 0, rect.h }
end

function Dock:apply()
    local ui, panels = self.ui, self.state.panels
    local width, height = ui.width, ui.height
    local barHeight = self.barHeight or 36
    if self.barWidth ~= width then
        self.barWidth = width
        barHeight = panels.toolbar:relayout(width)
        self.barHeight = barHeight
    end
    local p = self.preferred
    local key = ('%d|%d|%d|%d|%d|%d'):format(width, height, p.left, p.right, p.bottom, barHeight)
    if key == self.key then
        return
    end
    self.key = key
    local rects = Layout.compute(width, height, p, barHeight, Dock.STATUS)
    self.current = rects.sizes
    local frames = self.frames
    place(frames.top, rects.top)
    place(frames.left, rects.left)
    place(frames.right, rects.right)
    place(frames.bottom, rects.bottom)
    place(frames.status, rects.status)
    place(frames.splitLeft, rects.splitLeft)
    place(frames.splitRight, rects.splitRight)
    place(frames.splitBottom, rects.splitBottom)
    for _, name in ipairs({ 'tree', 'browser', 'properties' }) do
        local panel = panels[name]
        if panel and panel.resize then
            local rect = name == 'tree' and rects.left or name == 'properties' and rects.right or rects.bottom
            panel:resize(rect.w, rect.h)
        end
    end
    self.rects = rects
end

function Dock:update()
    local drag = self.drag
    if drag then
        if katsa.mouse.isDown(1) then
            local ui = self.ui
            local dx = (katsa.mouse.getX() - ui.offsetX) / ui.scale - drag.x
            local dy = (katsa.mouse.getY() - ui.offsetY) / ui.scale - drag.y
            local p = self.preferred
            if drag.name == 'splitLeft' then
                p.left = math.floor(drag.sizes.left + dx)
            elseif drag.name == 'splitRight' then
                p.right = math.floor(drag.sizes.right - dx)
            else
                p.bottom = math.floor(drag.sizes.bottom - dy)
            end
        else
            self.drag = nil
            self.state:savePrefs()
        end
    end
    self:apply()
end

return Dock
