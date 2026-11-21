local Config = require('source.engine.core.windowConfig')
local Optional = require('source.runtime.optional')

function katsa.conf(settings)
    Config.apply(
        settings,
        Optional.require('game.data.project') or require('source.runtime.project')
    )
end
