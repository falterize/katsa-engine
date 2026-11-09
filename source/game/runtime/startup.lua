local hasValidation, validationRegistry = pcall(require, 'validation.tests.registry')

local Startup = {
    createScene = require('source.game.runtime.application').new,
    managerOptions = { manifest = require('source.game.data.manifest') },
    -- validation/ is packaged only on request; without it the test registry is absent.
    registry = hasValidation and validationRegistry or nil,
}

-- Hot reload re-creates the running scene from disk; the scene is told apart by its zone id (or
-- the package path of a scene opened from a folder).
local function restartScene(manager, scene)
    local source = scene.options and scene.options.package or scene.zone
    assert(source, 'This scene cannot be re-created')
    manager:switch(require('source.game.runtime.application').new, source)
end

function Startup.beforeLoad(arguments)
    if os.getenv('KATSA_HOTRELOAD') == '1' then
        Startup.managerOptions.hotReload = { restart = restartScene }
    end
    local migrated, message = require('source.engine.core.saveData').migrate()
    if not migrated then
        print('Save data migration could not finish: ' .. tostring(message))
    end
    for _, argument in ipairs(arguments) do
        if argument == '--physics-oimo' then
            require('source.engine.physics').setDefaultBackend('oimo')
        elseif argument == '--hot-reload' then
            Startup.managerOptions.hotReload = { restart = restartScene }
        elseif argument == '--physics-jolt' then
            require('source.engine.physics').setDefaultBackend('jolt')
        end
    end
end

return Startup
