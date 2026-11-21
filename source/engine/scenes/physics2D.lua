local Physics2D = {}

function Physics2D.create(scene, options, ui)
    ui = ui or scene.root:find('World3D/World2D')
    local physics = ui:createPhysics(options or {})
    if ui == scene.root:find('World3D/World2D') then
        scene.physics2D = physics
    end
    return physics
end

return Physics2D
