local Cleanup = require('source.engine.core.cleanup')

local Scene = {}
local systemSettings = {
    simulation = { order = 10, enabled = true },
}

function Scene.create(scene, context)
    local Content = context:require('scripts.content')
    local state = Content.new(scene)
    state.scene = scene
    context.instance = state
    scene:preparePresentation()
    context:require('scripts.ui.interface').create(state)
    -- Discovered once at creation; order and startup are controlled by this scene.
    require('source.engine.scenes.systems').discover(scene, context, state, systemSettings)
    return state
end

function Scene.update(state, dt)
    state.scene.systems:update(dt)
end

function Scene.update3D(state, dt)
    state.scene.systems:update3D(dt)
end

function Scene.update2D(state, dt, realDt)
    local scene = state.scene
    scene.root:find('World3D/World2D'):update(realDt or dt, dt)
    for _, board in ipairs(scene.world.billboards) do
        board.ui:update(realDt or dt)
    end
    scene.systems:update2D(dt, realDt)
end

function Scene.destroy(state)
    Cleanup.run({
        function()
            state.scene.systems:release()
        end,
        function()
            if state.release then
                state:release()
            end
        end,
    })
end

return Scene
