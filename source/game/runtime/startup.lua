local hasValidation, validationRegistry = pcall(require, 'validation.tests.registry')

local Startup = {
    createScene = require('source.game.runtime.application').new,
    managerOptions = { manifest = require('source.game.data.manifest') },
    -- validation/ is packaged only on request; without it the test registry is absent.
    registry = hasValidation and validationRegistry or nil,
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
