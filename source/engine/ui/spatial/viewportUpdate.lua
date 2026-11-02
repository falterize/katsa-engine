local ipairs = require('../../math.array').ipairs

local V = {}

function V.update(list, dt)
    for _, node in ipairs(list) do
        if node:isA('UINode') and node.visible and node.enabled then
            if node:isA('ViewportFrame') then
                node:updateContents(dt)
            end
            V.update(node.children, dt)
        end
    end
end

return V
