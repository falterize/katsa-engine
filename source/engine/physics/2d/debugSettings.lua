local Settings = {}
function Settings.create(enabled)
    return {
        enabled = enabled == true,
        shapes = true,
        joints = true,
        centers = true,
        velocities = false,
        contacts = true,
        _settingsKind = 'Physics2DDebug',
    }
end
return Settings
