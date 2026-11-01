local Application = require('source.game.runtime.application')

local Factory = {}

function Factory.new(manager)
    return Application.new(manager, 'pause')
end

return Factory
