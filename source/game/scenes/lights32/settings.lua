local Settings = {
    layoutVersion = 3,
    id = 'lights32',
    title = '32 lights / resolution benchmark',
    category = 'Performance',
    tags = { 'lights', 'performance', 'benchmark', '3d' },
    physics = { backend = 'auto' },
    stress = { side = 4, lights = 32 },
}

return Settings
