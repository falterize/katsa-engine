local Application = require('./application')

local Factory = {}

function Factory.new(manager)
    return Application.new(manager, 'nodeCatalog')
end

return Factory
