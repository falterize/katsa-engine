-- Listener position, orientation, velocity and master volume.

local State = require('source.katsa.audio.state')
local Audio = State.Audio

local function setListener(field, ...)
    State.listener[field] = { ... }
    State.driver.updateListener(State.listener)
end

function Audio.setPosition(x, y, z)
    setListener('position', x, y, z)
end

function Audio.getPosition()
    return unpack(State.listener.position)
end

function Audio.setOrientation(fx, fy, fz, ux, uy, uz)
    setListener('orientation', fx, fy, fz, ux, uy, uz)
end

function Audio.getOrientation()
    return unpack(State.listener.orientation)
end

function Audio.setVelocity(x, y, z)
    setListener('velocity', x, y, z)
end

function Audio.getVelocity()
    return unpack(State.listener.velocity)
end

function Audio.setVolume(value)
    State.listener.volume = value
    State.driver.updateListener(State.listener)
end

function Audio.getVolume()
    return State.listener.volume
end
