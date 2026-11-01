local Startup = {
    createScene = require('source.game.runtime.application').new,
    managerOptions = { manifest = require('source.game.data.manifest') },
    registry = require('source.tests.registry'),
}

function Startup.beforeLoad(arguments)
    local migrated, message = require('source.engine.core.saveData').migrate()
    if not migrated then
        print('Save data migration could not finish: ' .. tostring(message))
    end
    for _, argument in ipairs(arguments) do
        if argument == '--physics-oimo' then
            require('source.engine.physics').setDefaultBackend('oimo')
        elseif argument == '--physics-jolt' then
            require('source.engine.physics').setDefaultBackend('jolt')
        end
    end
end

return Startup
