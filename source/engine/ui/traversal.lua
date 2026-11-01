local ipairs = require('source.engine.math.array').ipairs

local Traversal = {}

function Traversal.each(list, callback)
    for _, node in ipairs(list) do
        callback(node)
        Traversal.each(node.children, callback)
    end
end

return Traversal
