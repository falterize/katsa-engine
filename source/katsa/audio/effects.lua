-- Effect definitions, distance model and Doppler scale.

local State = require('source.katsa.audio.state')
local Audio = State.Audio

function Audio.isEffectsSupported()
    return State.driver.effectsSupported and true or false
end

function Audio.getMaxSourceEffects()
    return State.driver.maxSourceEffects or 0
end

function Audio.setEffect(name, settings)
    if settings == false then
        State.effects[name] = nil
        State.driver.removeEffect(name)
        return true
    end
    assert(type(settings) == 'table', 'Effect settings must be a table')
    State.effects[name] = settings
    State.driver.defineEffect(name, settings)
    return true
end

function Audio.getEffect(name)
    return State.effects[name]
end

function Audio.getActiveEffects()
    local list = {}
    for name in pairs(State.effects) do
        list[#list + 1] = name
    end
    table.sort(list)
    return list
end

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

function Audio.getSourceCount()
    return Audio.getActiveSourceCount()
end
