local Cleanup = require('source.engine.core.cleanup')

local Scene = {}
local systemSettings = {
    simulation = { order = 10, enabled = true },
}

function Scene.create(scene, context)
    local Content = context:require('scripts.content')
    local state = Content.create(scene)
    state.scene = scene
    context.instance = state
    if scene.preparePresentation then
        scene:preparePresentation()
    end
    context:require('scripts.ui.interface').create(state)
    local systems = state.scene.systems
    -- Discover once at creation; order and startup are controlled by this scene.
    local entries = {}
    for _, filename in ipairs(love.filesystem.getDirectoryItems(context.root .. '/systems')) do
        if
            filename:match('%.lua$')
            and love.filesystem.getInfo(context.root .. '/systems/' .. filename, 'file')
        then
            local name =
                assert(filename:match('^([%w_]+)%.lua$'), 'Invalid system module: ' .. filename)
            local settings = systemSettings[name] or { order = 100, enabled = true }
            entries[#entries + 1] =
                { name = name, settings = settings, order = settings.order or 100 }
        end
    end
    table.sort(entries, function(a, b)
        if a.order == b.order then
            return a.name < b.name
        end
        return a.order < b.order
    end)
    for _, entry in ipairs(entries) do
        local Module = context:require('systems.' .. entry.name)
        assert(
            type(Module.create) == 'function',
            'System must export create(state, scene, context)'
        )
        systems:add(
            entry.name,
            Module.create(state, scene, context, entry.settings),
            entry.settings.enabled
        )
    end
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
    scene.ui:update(realDt or dt, dt)
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
