-- Effect definitions and support queries.

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

function Audio.getSourceCount()
    return Audio.getActiveSourceCount()
end
