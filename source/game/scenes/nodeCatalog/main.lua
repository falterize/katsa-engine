local Cleanup = require('source.engine.core.cleanup')

local Scene = {}
local systemSettings = {}

function Scene.create(scene, context)
    local Controller = context:require('scripts.ui.controller')
    local state = Controller.new(scene.manager)
    context.instance = state
    scene.state = state
    state.scene = scene
    state.package = context
    state.systems = require('source.engine.scenes.systems').new(state)
    state:load()
    local systems = state.systems
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
    state.systems:update(dt)
end

function Scene.update3D(state, dt)
    state.world:updateNodes(dt)
    state.systems:update3D(dt)
end

function Scene.update2D(state, dt, realDt)
    state.ui:update(realDt or dt)
    if state.update then
        state:update(dt, realDt)
    end
    state.systems:update2D(dt, realDt)
end

function Scene.destroy(state)
    Cleanup.run({
        function()
            state.systems:release()
        end,
        function()
            if state.release then
                state:release()
            end
        end,
    })
end

return Scene
