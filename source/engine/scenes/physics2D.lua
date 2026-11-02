local Physics2D = {}

function Physics2D.create(scene, options, ui)
    ui = ui or scene.ui
    local settings =
        require('./loader').configure(options or {}, scene.settings.physics2D)
    local physics = ui:createPhysics(settings)
    if ui == scene.ui then
        scene.physics2D = physics
    end
    return physics
end

return Physics2D
