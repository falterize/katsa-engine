local Settings = {
    layoutVersion = 3,
    server = 'server.main', -- the dedicated server entry used by --server
    version = '1.0.0a',
    nodes = { 'vehicle' },
    plugins = { 'pathfinding' }, -- NavMap3D node and its debug view
    cameraButtons = false, -- no UP/DOWN: the chase camera is orbited by dragging
    physics = { backend = 'jolt' },
}

return Settings
