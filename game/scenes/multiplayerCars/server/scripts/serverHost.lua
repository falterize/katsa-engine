-- A game server with its own physics-only World3D: no window content, no meshes, no camera.
-- A dedicated server process runs one of these, and so does a hosting player's process, so a host
-- plays through the network exactly like every other client.
local World3D = require('source.engine.world.world')
local Plugins = require('source.engine.plugins')
local RootNode = require('source.engine.scenes.rootNode')
local Statics = require('../../scripts.shared.arenaStatics')
local GameServer = require('./gameServer')

local ServerHost = {}
ServerHost.__index = ServerHost

-- resources: a resource scope that outlives the server. options: everything GameServer takes
-- (port, name, maxPlayers, simulate, bot ...); `world` is created here.
function ServerHost.new(resources, options)
    options = options or {}
    local world = World3D.new(resources, nil, {
        physics = {
            unitsPerMeter = 1,
            gravity = { 0, -9.81, 0 },
            backend = 'jolt',
            fixedDelta = 1 / 60,
        },
    })
    local root = RootNode.create(world)
    Plugins.activate(world, { 'pathfinding' })
    Statics.build({ world = world })
    local settings = {}
    for key, value in pairs(options) do
        settings[key] = value
    end
    settings.world = world
    return setmetatable({
        world = world,
        root = root,
        game = GameServer.new({}, settings),
        options = options,
    }, ServerHost)
end

function ServerHost:start()
    self.game:start()
    return self
end

-- One frame: step the physics, then let the server read the bodies and talk to the clients.
function ServerHost:update(dt)
    self.world.physics:update(dt)
    self.game:update(dt)
end

function ServerHost:getServer()
    return self.game.server
end

function ServerHost:stop()
    self.game:stop()
    self.root:destroy()
end

return ServerHost
