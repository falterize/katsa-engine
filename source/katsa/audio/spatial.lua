-- Distance model and Doppler scale.

local State = require('source.katsa.audio.state')
local Audio = State.Audio

function Audio.getDistanceModel()
    return State.distanceModel or 'inverseclamped'
end

function Audio.setDistanceModel(model)
    State.distanceModel = model
    if State.driver.updateGlobal then
        State.driver.updateGlobal(State)
    end
end

function Audio.getDopplerScale()
    return State.doppler or 1
end

function Audio.setDopplerScale(value)
    State.doppler = value
    if State.driver.updateGlobal then
        State.driver.updateGlobal(State)
    end
end
