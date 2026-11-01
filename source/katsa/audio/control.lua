-- Driver selection and playback control of groups of sources.

local State = require('source.katsa.audio.state')
local Audio = State.Audio

function Audio.setDriver(newDriver)
    State.driver = newDriver
    State.driverChosen = true
end

function Audio.getDriver()
    return State.driver
end

local function each(list, fn)
    for source in pairs(State.sources) do
        if not list or list[source] then
            fn(source)
        end
    end
end

local function eachMember(sources, method)
    for _, source in ipairs(sources) do
        if type(source) == 'table' and source[method] then
            source[method](source)
        else
            for _, member in ipairs(source) do
                member[method](member)
            end
        end
    end
end

function Audio.play(...)
    eachMember({ ... }, 'play')
end

function Audio.stop(...)
    if select('#', ...) == 0 then
        each(nil, function(source)
            source:stop()
        end)
        return
    end
    eachMember({ ... }, 'stop')
end

function Audio.pause(...)
    if select('#', ...) == 0 then
        local paused = {}
        each(nil, function(source)
            if source._state == 'playing' then
                source:pause()
                paused[#paused + 1] = source
            end
        end)
        return paused
    end
    eachMember({ ... }, 'pause')
end

function Audio.getActiveSourceCount()
    local count = 0
    each(nil, function(source)
        if source:isPlaying() then
            count = count + 1
        end
    end)
    return count
end
