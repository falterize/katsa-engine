-- State of the launcher showcase: the instance list and which entry is selected.
local Demo = {}
Demo.__index = Demo

function Demo.new(scene)
    scene.ui.layoutMode = 'Viewport'
    scene.showStats = false
    scene.camera.position = { 0, 30, -80 }
    scene.world.environment.debug.gizmos.enabled = false
    return setmetatable({
        scene = scene,
        selected = 3,
        groups = {
            {
                name = 'Vanilla',
                instances = {
                    { name = '1.21.4', version = 'Minecraft 1.21.4', played = 'Today', hours = 31 },
                    { name = 'Snapshot Lab', version = 'Minecraft 25w05a', played = 'Yesterday', hours = 6 },
                    { name = 'Survival World', version = 'Minecraft 1.20.1', played = '3 days ago', hours = 142 },
                },
            },
            {
                name = 'Modded',
                instances = {
                    { name = 'Create: Above and Beyond', version = 'Fabric 1.20.1', played = 'Last week', hours = 58 },
                    { name = 'Performance Pack', version = 'Quilt 1.21.1', played = '2 weeks ago', hours = 12 },
                    { name = 'Skyblock Remix', version = 'NeoForge 1.21.1', played = 'Never', hours = 0 },
                },
            },
        },
    }, Demo)
end

function Demo:update(dt)
    self.scene.world:updateNodes(dt)
end

return Demo
