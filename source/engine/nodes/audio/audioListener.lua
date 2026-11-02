-- AudioListener: places the "ears" of a scene. While at least one enabled AudioListener exists,
-- the first one in creation order replaces the camera as the listener position and orientation.
local ipairs = require('../../math.array').ipairs
local Node = require('../core.baseNode')

local Listener = Node.define('AudioListener', 'Node3D')
Listener.propertySchema = { enabled = {}, status = { readOnly = true } }

function Listener.initialize(self)
    self.enabled = self.enabled ~= false
    self.status = 'Idle'
end

function Listener.mount(world, properties, parent)
    assert(world.audio, 'World3D.audio must be assigned before creating sound nodes')
    properties._audio = world.audio
    local node = Node.new('AudioListener', properties, parent)
    local listeners = world.audio.listeners
    listeners[#listeners + 1] = node
    node:onDestroy(function()
        for i, entry in ipairs(listeners) do
            if entry == node then
                table.remove(listeners, i)
                break
            end
        end
    end)
    return node
end

-- Position, forward (+Z) and up (+Y) of the listener in world space.
function Listener:getPose(position, forward, up)
    local m = self:getWorldMatrix()
    position, forward, up = position or {}, forward or {}, up or {}
    position[1], position[2], position[3] = m[4], m[8], m[12]
    local fx, fy, fz = m[3], m[7], m[11]
    local length = math.sqrt(fx * fx + fy * fy + fz * fz)
    forward[1], forward[2], forward[3] = fx / length, fy / length, fz / length
    local ux, uy, uz = m[2], m[6], m[10]
    length = math.sqrt(ux * ux + uy * uy + uz * uz)
    up[1], up[2], up[3] = ux / length, uy / length, uz / length
    return position, forward, up
end

return Listener
