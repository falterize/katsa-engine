local ipairs = require('source.engine.math.array').ipairs
-- Finish every shutdown action before propagating the first failure.
local Cleanup = {}

function Cleanup.run(actions)
    local firstError
    for _, action in ipairs(actions) do
        local ok, message = pcall(action)
        if not ok then
            firstError = firstError or message
        end
    end
    if firstError then
        error(firstError, 0)
    end
end

return Cleanup
