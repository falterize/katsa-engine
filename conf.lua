local Config = require('source.engine.core.windowConfig')

function katsa.conf(settings)
    Config.apply(settings, require('source.game.data.project'))
end
