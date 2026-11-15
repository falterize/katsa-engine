local Scene = {}
Scene.__index = Scene

function Scene.new(scene, context)
    local self = setmetatable({ scene = scene }, Scene)
    self.counter = scene.world:create('Counter', { name = 'SceneCounter' })
    local Counter = context:require('systems.counter')
    self.system = scene.systems:add('counter', Counter.new(self.counter), true)
    scene:createPhysics3D()
    return self
end

function Scene:buildUI()
    self.scene.root:find('World3D/World2D'):create('ImageRect', {
        name = 'LocalImage',
        image = 'scene://textures/checker.png',
        size = { 0, 48, 0, 48 },
    }, self.scene.root:find('World3D/World2D').content)
    self.scene.root:find('World3D/World2D'):create('ImageRect', {
        name = 'SharedImage',
        image = 'shared://textures/engine/white.png',
        position = { 0, 56, 0, 0 },
        size = { 0, 48, 0, 48 },
    }, self.scene.root:find('World3D/World2D').content)
end

function Scene:update(dt)
    self.scene.physics:update(dt)
    self.scene.world:updateNodes(dt)
end

return Scene
