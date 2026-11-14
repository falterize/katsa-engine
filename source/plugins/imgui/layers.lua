-- ImGuiLayer nodes that exist, so the host can ask each one to draw. Weak: a destroyed node
-- disappears from the list without bookkeeping.
local Layers = setmetatable({}, { __mode = 'k' })

return Layers
