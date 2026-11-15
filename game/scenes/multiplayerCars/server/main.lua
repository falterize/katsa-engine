-- Dedicated server entry (`--server`): no menu, no views and no input; the scene only hosts the
-- game server and its console. Nothing under server/ may require client code.
local Server = {}

function Server.create(scene, context)
    local Dedicated = context:require('server.scripts.dedicated')
    local options = Dedicated.parse(katsa.launchArguments)
    assert(options, 'The server entry runs with --server')
    local state = Dedicated.new(scene, options)
    context.instance = state
    return state
end

function Server.update(state, dt)
    state:update(dt)
end

function Server.update3D() end

function Server.update2D() end

function Server.destroy(state)
    state:release()
end

return Server
