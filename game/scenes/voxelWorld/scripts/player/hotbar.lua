-- Hotbar state: nine slots holding block ids, the selected slot and the block picker panel.
local Hotbar = {}
Hotbar.__index = Hotbar

function Hotbar.new(blocks)
    local self = setmetatable({ blocks = blocks, slots = {}, selected = 1, listeners = {} }, Hotbar)
    for i = 1, 9 do
        self.slots[i] = i
    end
    return self
end

function Hotbar:onChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

local function changed(self)
    for _, fn in ipairs(self.listeners) do
        fn(self)
    end
end

function Hotbar:current()
    return self.slots[self.selected]
end

function Hotbar:select(slot)
    self.selected = slot
    changed(self)
end

function Hotbar:scroll(step)
    self.selected = (self.selected - 1 + step) % 9 + 1
    changed(self)
end

function Hotbar:set(id)
    self.slots[self.selected] = id
    changed(self)
end

-- The block picker panel belongs to the UI, which installs `picker = { toggle, hide }`.
function Hotbar:togglePicker()
    self.picker.toggle()
end

function Hotbar:hidePicker()
    self.picker.hide()
end

return Hotbar
