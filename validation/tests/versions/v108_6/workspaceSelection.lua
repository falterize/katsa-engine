-- The Workspace clears its property panel when the selected node is destroyed (it used to call an
-- undefined global and crash the editor update).
local Workspace = require('source.engine.editor.workspace')

local Module = {}

function Module.run(self)
    local destroyed = 0
    local children = {}
    for index = 1, 3 do
        children[index] = {
            destroy = function()
                destroyed = destroyed + 1
                table.remove(children)
            end,
        }
    end
    local panel = { properties = { children = children }, propertyButtons = { {} } }
    Workspace.clearInspector(panel)
    self:check(destroyed == 3 and #children == 0, 'clearInspector destroys every property row')
    self:check(next(panel.propertyButtons) == nil, 'clearInspector forgets the property buttons')
end

return Module
