local Settings = {
    layoutVersion = 3,
    id = 'lights',
    title = 'Many lights / 64 candidates',
    category = 'Performance',
    tags = { 'lights', 'performance', '3d' },
    physics = { backend = 'auto' },
    stress = { side = 4, lights = 64 },
}

return Settings
