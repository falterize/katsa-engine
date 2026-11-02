-- SoundManager: the scene-level control surface for audio. It owns no state of its own; volumes and
-- mute flags live in the Audio scope's group table, so every consumer (Sound nodes, AudioSource
-- nodes, direct Audio:play calls and the UI layer) sees one consistent mix.
local ipairs = require('../math.array').ipairs
local Validation = require('./validation')

local Manager = {}
Manager.__index = Manager

function Manager.new(audio)
    return setmetatable({ audio = audio }, Manager)
end

function Manager:setMasterVolume(volume)
    self.audio:setGroupVolume('master', volume)
    return self
end

function Manager:getMasterVolume()
    return self.audio:getGroupVolume('master')
end

function Manager:setMuted(muted)
    self.audio:setGroupMuted('master', muted)
    return self
end

function Manager:isMuted()
    return self.audio.groups.master.muted == true
end

function Manager:createGroup(name, options)
    return self.audio:addGroup(name, options)
end

function Manager:hasGroup(name)
    return self.audio.groups[name] ~= nil
end

function Manager:setGroupVolume(name, volume)
    self.audio:setGroupVolume(name, volume)
    return self
end

function Manager:getGroupVolume(name)
    return self.audio:getGroupVolume(name)
end

function Manager:setGroupMuted(name, muted)
    self.audio:setGroupMuted(name, muted)
    return self
end

-- Effective gain of a group after all ancestors and mute flags.
function Manager:getGroupGain(name)
    return self.audio:groupGain(name)
end

function Manager:getGroupNames()
    local names = {}
    for name in pairs(self.audio.groups) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- Fire-and-forget playback. Returns the voice, which can be stopped with voice:release().
function Manager:play(resource, options)
    options = options or {}
    local group = options.group or 'effects'
    assert(self.audio.groups[group], 'Unknown sound group: ' .. tostring(group))
    local voiceOptions = {}
    for key, value in pairs(options) do
        voiceOptions[key] = value
    end
    voiceOptions.group = group
    return self.audio:play(resource, voiceOptions)
end

function Manager:getVoiceCount()
    return #self.audio.voices
end

function Manager:getSourceNodes()
    return self.audio.nodes
end

function Manager:stopAll()
    for _, node in ipairs(self.audio.nodes) do
        if not node.destroyed then
            node:stop()
        end
    end
    for i = #self.audio.voices, 1, -1 do
        self.audio.voices[i]:release()
        table.remove(self.audio.voices, i)
    end
    return self
end

function Manager:pauseAll()
    self.audio:pause()
    return self
end

function Manager:resumeAll()
    self.audio:resume()
    return self
end

function Manager:isPaused()
    return self.audio.paused == true
end

-- The listener that currently receives sound: the first enabled AudioListener in creation
-- order, or nil when the scene camera supplies the listener.
function Manager:getActiveListener()
    for _, listener in ipairs(self.audio.listeners) do
        if not listener.destroyed and listener.enabled ~= false then
            return listener
        end
    end
    return nil
end

Manager.validateVolume = Validation.unit

return Manager
