local Scene = {}

function Scene.create(scene, context)
    local state = { scene = scene }
    state.counter = scene.world:create('Counter', { name = 'SceneCounter' })
    local Counter = context:require('systems.counter')
    state.system = scene.systems:add('counter', Counter.new(state.counter), true)
    scene:createPhysics3D({ backend = 'oimo' })
    scene:preparePresentation()
    local ui = scene.root:find('World3D/World2D')
    ui:create('ImageRect', {
        name = 'LocalImage',
        image = 'scene://textures/checker.png',
        size = { 0, 48, 0, 48 },
    }, ui.content)
    ui:create('ImageRect', {
        name = 'SharedImage',
        image = 'shared://textures/surfaces/stone.png',
        position = { 0, 56, 0, 0 },
        size = { 0, 48, 0, 48 },
    }, ui.content)
    return state
end

function Scene.update(state, dt)
    state.scene.systems:update(dt)
    state.scene.physics:update(dt)
    state.scene.world:updateNodes(dt)
end

function Scene.update3D() end

function Scene.update2D() end

function Scene.destroy() end

return Scene
