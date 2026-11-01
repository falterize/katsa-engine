local ipairs = require('source.engine.math.array').ipairs
-- Install one cohesive responsibility on the public class.
local Voice = require('source.engine.audio.voice')
local Validation = require('source.engine.audio.validation')
local modes, unit = Validation.modes, Validation.unit
local Playback = {}

function Playback.install(Audio)
    local function loadSamples(path, spatialStereo)
        assert(love.filesystem.getInfo(path), 'Missing sound: ' .. path)
        local list
        if spatialStereo then
            local data = love.sound.newSoundData(path)
            local channels = data:getChannelCount()
            assert(channels <= 2, 'Spatial audio supports mono or stereo files: ' .. path)
            list = {}
            for channel = 1, channels do
                local mono = love.sound.newSoundData(
                    data:getSampleCount(),
                    data:getSampleRate(),
                    data:getBitDepth(),
                    1
                )
                for i = 0, data:getSampleCount() - 1 do
                    mono:setSample(i, data:getSample(i, channel))
                end
                list[channel] = love.audio.newSource(mono, 'static')
                mono:release()
            end
            data:release()
        else
            list = { love.audio.newSource(path, 'static') }
        end

        return list
    end

    function Audio:preload(path, spatialStereo)
        path = self.resources:canonical(path)
        local key = path .. (spatialStereo and '|spatial' or '|flat')
        if self.samples[key] then
            return self.samples[key]
        end
        local list = self.resources:cached('sound', key, function(owner)
            local samples = loadSamples(path, spatialStereo)
            for _, sample in ipairs(samples) do
                owner:own(sample)
            end
            return samples
        end)
        self.samples[key] = list
        return list
    end

    function Audio:play(path, options)
        options = options or {}
        path = self.resources:canonical(path)
        assert(love.filesystem.getInfo(path), 'Missing sound: ' .. path)
        local spatial = options.object ~= nil or options.position ~= nil
        local stream = options.stream or options.music or false
        local minDistance = options.minDistance or options.referenceDistance or 20
        local maxDistance = options.maxDistance or 300
        local mode = options.rolloff or 'LinearSquare'
        assert(
            type(minDistance) == 'number'
                and minDistance >= 0
                and type(maxDistance) == 'number'
                and maxDistance > minDistance
                and maxDistance < math.huge,
            'Audio requires 0 <= minDistance < maxDistance'
        )
        assert(modes[mode], 'Audio rolloff must be Linear, LinearSquare or Inverse')
        local group = options.group or (options.music and 'music' or 'effects')
        self:groupGain(group)
        unit(options.volume or 1, 'Voice volume')
        assert(
            type(options.pitch or 1) == 'number'
                and (options.pitch or 1) > 0
                and (options.pitch or 1) <= 8,
            'Invalid voice pitch'
        )
        assert(
            type(options.stereoWidth or 4) == 'number'
                and (options.stereoWidth or 4) >= 0
                and (options.stereoWidth or 4) < math.huge,
            'Invalid stereoWidth'
        )
        local sources = {}
        if stream then
            sources[1] = love.audio.newSource(path, 'stream')
            if spatial and sources[1]:getChannelCount() ~= 1 then
                sources[1]:release()
                error(
                    'Spatial stereo streaming is not supported. Use a mono stream or a static stereo sound: '
                        .. path
                )
            end
        else
            for i, sample in ipairs(self:preload(path, spatial)) do
                sources[i] = sample:clone()
            end
        end
        local voice = setmetatable({
            mixer = self,
            source = sources[1],
            sources = sources,
            group = group,
            volume = options.volume or 1,
            pitch = options.pitch or 1,
            object = options.object,
            position = options.position,
            spatial = spatial,
            stereoWidth = options.stereoWidth or 4,
            minDistance = minDistance,
            maxDistance = maxDistance,
            rolloff = mode,
            timeScaled = options.timeScaled ~= false,
            manualPause = options.autoplay == false,
            gain = 1,
        }, Voice)
        assert(
            voice.pitch > 0 and voice.pitch <= 8 and voice.stereoWidth >= 0,
            'Invalid voice pitch or stereoWidth'
        )
        for _, source in ipairs(sources) do
            source:setLooping(options.loop or false)
            if source:getChannelCount() == 1 then
                source:setRelative(not spatial)
            end
            if spatial then
                -- Attenuate explicitly so maxDistance is a hard silence boundary, independent of OpenAL's model.
                source:setRolloff(0)
                source:setAttenuationDistances(math.max(0.001, minDistance), maxDistance)
            end
        end
        self.voices[#self.voices + 1] = voice
        self:apply(voice)
        if voice.timePaused then
            voice.timeWasPlaying = true
        end
        if self.paused then
            voice.wasPlaying = true
        end
        if options.autoplay ~= false and not self.paused and not voice.timePaused then
            for _, source in ipairs(sources) do
                source:play()
            end
        end
        return voice
    end
end

return Playback
