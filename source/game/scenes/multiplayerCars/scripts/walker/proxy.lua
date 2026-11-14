-- The solid stand-in of another player's walker. Every client simulates only its own walker, so
-- without this a player would walk straight through everybody else. The proxy is a kinematic
-- capsule that follows the replicated, interpolated pose; it stops colliding while its player
-- rides a car (the seated body is not solid, like the local one).
local WalkerEntity = require('../shared.walkerEntity')
local Walker = require('./controller')

local Proxy = {}
Proxy.__index = Proxy

function Proxy.new(world, netId, model)
    local settings = Walker.settings
    local cylinder = settings.standingHeight - 2 * settings.radius
    local node = world:create('Body3D', {
        name = 'WalkerProxy' .. netId,
        bodyType = 'Kinematic',
        position = { model.x, model.y + settings.standingHeight / 2, model.z },
        size = { settings.radius * 2, settings.standingHeight, settings.radius * 2 },
        collider = { shape = 'Capsule', radius = settings.radius, height = cylinder },
        friction = 0,
        restitution = 0,
    })
    return setmetatable({ node = node, model = model, half = settings.standingHeight / 2 }, Proxy)
end

-- Moves the capsule to the pose the character is drawn at. Call once per frame.
function Proxy:update()
    local model = self.model
    local state = WalkerEntity.states[model.state or 1]
    self.node.canCollide = state ~= 'drive' and state ~= 'passenger'
    self.node.position = {
        model.rx or model.x,
        (model.ry or model.y) + self.half,
        model.rz or model.z,
    }
    self.node.physics:sync()
end

function Proxy:destroy()
    self.node:destroy()
end

return Proxy
