-- Inspector field policy: a key listed twice shows the property twice (fog density did).
local Policy = require('source.engine.editor.inspectors.propertyPolicy')

local Module = {}

function Module.run(self)
    local seen, duplicate = {}, nil
    for _, key in ipairs(Policy.fields) do
        if seen[key] then
            duplicate = key
        end
        seen[key] = true
    end
    self:check(duplicate == nil, 'the inspector field list has no repeated key ' .. tostring(duplicate or ''))
end

return Module
