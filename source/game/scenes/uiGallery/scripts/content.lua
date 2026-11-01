local ipairs = require('source.engine.math.array').ipairs

local Demo = {}
Demo.__index = Demo

function Demo.new(scene)
    scene.ui.layoutMode = 'Viewport'
    scene.showStats = false
    scene.camera.position = { 0, 30, -80 }
    scene.world.environment.debug.gizmos.enabled = false
    return setmetatable({ scene = scene, presses = 0 }, Demo)
end

function Demo:update(dt)
    local narrow = self.scene.ui.width < 600
    self.root.position = { 0.5, 0, 0.5, 44 }
    self.root.size = { 1, -24, 1, -166 }
    self.left.size = narrow and { 1, -36, 1, -85 } or { 0.48, -20, 1, -85 }
    self.right.visible = not narrow
    -- The narrow layout keeps both sections accessible in a single scroll view.
    if narrow ~= self.narrow then
        self.narrow = narrow
        self.right.parent = narrow and self.left or self.root
        self.right.position = narrow and { 0, 0, 0, 1040 } or { 0.5, 0, 0, 65 }
        self.right.size = narrow and { 1, 0, 0, 400 } or { 0.5, -18, 1, -85 }
        self.right.visible = true
        self.left.length = narrow and 1500 or 1040
    end
    self.right.visible = true
    self.scene.world:updateNodes(dt)
end

return Demo
