local Localization = require('source.engine.localization')

local Content = {}
Content.__index = Content

function Content.new(scene)
    scene.ui.layoutMode = 'Viewport'
    scene.showStats = false
    scene.camera.position = { 0, 30, -80 }
    scene.world.environment.debug.gizmos.enabled = false
    local service = Localization.get()
    service:loadDirectory(scene.resources, 'shared://locales')
    service:setLocale(service:detect())
    return setmetatable({ scene = scene, items = 1, service = service }, Content)
end

function Content:update(dt)
    self.scene.world:updateNodes(dt)
end

return Content
