-- Video playback engine: a decoder thread (video/worker.lua, FFmpeg) fills a ring of RGBA frames in
-- shared memory, this side shows the frame that is due on a GPU image and plays the audio through a
-- queue source. The audio device clock is the master clock; without sound a wall clock is used.
--
--   local player, message = Player.new({ path = 'clip.mp4', loop = true })
--   player:play(); player:update(dt)        -- every frame
--   player.image                            -- a katsa Image, valid once player.state ~= 'loading'
--
-- States: 'loading', 'ready' (first frame shown, not started), 'playing', 'paused', 'finished',
-- 'error' (player.error says why). Only real files can be decoded: a path inside an archive is
-- copied to the save directory first.
local Player = {}
Player.__index = Player

local MAX_RING_BYTES = 96 * 1024 * 1024
local EPSILON = 1 / 240

local function readSource(path)
    local data = katsa.filesystem.read(path)
    if not data then
        local file = io.open(path, 'rb')
        if file then
            data = file:read('*a')
            file:close()
        end
    end
    return data
end

-- A path FFmpeg can open: a real file as it is, otherwise a copy in the save directory.
function Player.resolveFile(path)
    local Native = require('source.katsa.core.nativeLib')
    if Native.stat(path) == 'file' then
        return path
    end
    local directory = katsa.filesystem.getRealDirectory(path)
    if directory then
        local candidate = directory .. '/' .. path
        if Native.stat(candidate) == 'file' then
            return candidate
        end
    end
    local data = katsa.filesystem.read(path)
    if not data then
        return nil, 'Video file not found: ' .. tostring(path)
    end
    local name = 'video-cache/' .. path:gsub('[^%w%.%-_]', '_')
    katsa.filesystem.createDirectory('video-cache')
    katsa.filesystem.write(name, data)
    return katsa.filesystem.getSaveDirectory() .. '/' .. name
end

-- True when FFmpeg and the worker threads are available.
function Player.isSupported()
    local Libav = require('source.engine.video.libav')
    return Libav.available() and katsa.thread and katsa.thread.isSupported()
end

-- options: path (required), loop, volume, speed, maxHeight (0 = native), pixelate, autoplay,
-- onFinished() and onLooped() callbacks (called from update).
function Player.new(options)
    local Libav = require('source.engine.video.libav')
    local ok, message = Libav.load()
    if not ok then
        return nil, 'FFmpeg libraries are not available: ' .. tostring(message)
    end
    if not (katsa.thread and katsa.thread.isSupported()) then
        return nil, 'Worker threads are not available'
    end
    local file, problem = Player.resolveFile(options.path)
    if not file then
        return nil, problem
    end
    local self = setmetatable({
        path = options.path,
        loop = options.loop == true,
        volume = options.volume or 1,
        speed = options.speed or 1,
        pixelate = options.pixelate == true,
        onFinished = options.onFinished,
        onLooped = options.onLooped,
        state = 'loading',
        wall = 0,
        epoch = 0,
        playing = false,
        rate = 0,
    }, Player)
    local modules = {}
    for _, name in ipairs({ 'libav', 'decoder' }) do
        modules['source.engine.video.' .. name] = readSource('source/engine/video/' .. name .. '.lua')
    end
    self.thread = katsa.thread.spawn({
        name = 'video',
        script = assert(readSource('source/engine/video/worker.lua'), 'worker script missing'),
        scriptName = 'video worker',
        modules = modules,
    })
    self.thread.onError = function(text)
        self:fail(text)
    end
    self.thread:on('audio', function(chunk)
        self:onAudio(chunk)
    end)
    self.thread:request('open', { path = file, maxHeight = options.maxHeight or 0 }, function(good, info)
        if not good or info.error then
            self:fail(good and info.error or tostring(info))
        else
            self:onOpened(info)
        end
    end)
    if options.autoplay then
        self.wantPlay = true
    end
    return self
end

function Player:fail(message)
    self.state, self.error = 'error', message
    self.playing = false
end

function Player:onOpened(info)
    local SharedArray = katsa.thread.SharedArray
    self.width, self.height, self.duration, self.fps = info.width, info.height, info.duration, info.fps
    self.hasAudio, self.sampleRate, self.channels = info.hasAudio, info.sampleRate, info.channels
    local frameBytes = info.width * info.height * 4
    local slots = math.max(3, math.min(8, math.floor(MAX_RING_BYTES / frameBytes)))
    self.slots, self.frameBytes = slots, frameBytes
    self.control = SharedArray.new('int32_t', 4)
    self.times = SharedArray.new('double', slots)
    self.frames = SharedArray.new('uint8_t', slots * frameBytes)
    local blank = katsa.image.newImageData(self.width, self.height)
    self.image = katsa.graphics.newImage(blank)
    local filter = self.pixelate and 'nearest' or 'linear'
    self.image:setFilter(filter, filter)
    if self.hasAudio then
        self.audio = katsa.audio.newQueueSource(self.sampleRate, self.channels)
        self.audio.autoplay = false
        self.audio:setVolume(self.volume)
    end
    self.thread:request('attach', {
        control = self.control:getHandle(),
        times = self.times:getHandle(),
        frames = self.frames:getHandle(),
        slots = slots,
        frameBytes = frameBytes,
    }, function() end)
    self.state = 'ready'
    self.needFrame = true
end

function Player:onAudio(chunk)
    if chunk.epoch ~= self.epoch or not self.audio then
        return
    end
    if not self.audioStarted then
        self.audioBase = chunk.pts
        self.audioStarted = true
    end
    self.audio:queue(chunk.pcm, chunk.frames)
    if self.playing and self.speed == 1 and not self.audioRunning then
        self.audio:resume()
        self.audioRunning = true
    end
end

function Player:getTime()
    if self.audioRunning then
        local played = self.audio:getPlayedSeconds()
        if played then
            -- The wall clock follows the audio one, so it takes over without a jump.
            self.wall = (self.audioBase or 0) + played
            return self.wall
        end
    end
    return self.wall
end

function Player:play()
    if self.state == 'finished' then
        self:seek(0)
    end
    self.wantPlay = true
    if self.state == 'ready' or self.state == 'paused' then
        self:start()
    end
end

function Player:start()
    self.state, self.playing = 'playing', true
    if self.audio and self.audioStarted and self.speed == 1 then
        self.audio:resume()
        self.audioRunning = true
    end
end

function Player:pause()
    self.wantPlay = false
    if self.state == 'playing' then
        self.wall = self:getTime()
        self.state, self.playing = 'paused', false
        if self.audio then
            self.audio:pause()
        end
        self.audioRunning = false
    end
end

function Player:stop()
    self:pause()
    self:seek(0)
    if self.state ~= 'error' and self.state ~= 'loading' then
        self.state = 'ready'
    end
end

function Player:setVolume(volume)
    self.volume = volume
    if self.audio then
        self.audio:setVolume(volume)
    end
end

function Player:setSpeed(speed)
    if speed == self.speed then
        return
    end
    self.wall = self:getTime()
    self.speed = speed
    if self.audio and self.audioRunning and speed ~= 1 then
        self.audio:pause() -- no pitch correction: sound is muted off normal speed
        self.audioRunning = false
    end
end

function Player:seek(time)
    if not self.slots then
        self.pendingSeek = time
        return
    end
    time = math.max(0, math.min(time, math.max(self.duration - 0.001, 0)))
    self.epoch = self.epoch + 1
    self.seeking = true
    self.wall, self.audioStarted, self.audioRunning, self.audioBase = time, false, false, nil
    self.target = time > 0 and time or nil
    self.needFrame = true
    if self.audio then
        self.audio:clear()
    end
    if self.state == 'finished' then
        self.state = self.wantPlay and 'playing' or 'paused'
        self.playing = self.state == 'playing'
    end
    self.thread:request('seek', { time = time, epoch = self.epoch }, function(good, result)
        if good and result == self.epoch then
            self.seeking = false
        end
    end)
end

-- Uploads the ring frame at `slot` to the GPU image.
local function upload(self, slot)
    self.image:replaceRaw(self.frames.data + slot * self.frameBytes, self.width, self.height)
end

local function present(self, now)
    local control, times = self.control, self.times
    local read, written = control:load(1), control:load(0)
    while read < written do
        local slot = read % self.slots
        local target = self.target
        -- After a seek the decoder starts at the keyframe before the target: those frames are dropped.
        if target and times.data[slot] < target - 0.5 / math.max(self.fps, 1) then
            read = read + 1
            control:store(1, read)
        elseif times.data[slot] > now + EPSILON then
            break
        else
            self.target = nil
            local newer = read + 1 < written and times.data[(read + 1) % self.slots] <= now + EPSILON
            if not newer then
                upload(self, slot)
                self.shown = times.data[slot]
                self.needFrame = false
                self.frameCount = (self.frameCount or 0) + 1
                read = read + 1
                control:store(1, read)
                return
            end
            read = read + 1
            control:store(1, read)
        end
    end
    -- A paused or just-opened player still wants its first frame, due or not.
    if self.needFrame and read < written and not self.target then
        local slot = read % self.slots
        upload(self, slot)
        self.shown = times.data[slot]
        self.needFrame = false
        self.frameCount = (self.frameCount or 0) + 1
        control:store(1, read + 1)
    end
end

function Player:update(dt)
    local thread = self.thread
    if not thread then
        return
    end
    thread:poll()
    if self.state == 'loading' or self.state == 'error' then
        return
    end
    if self.pendingSeek then
        local time = self.pendingSeek
        self.pendingSeek = nil
        self:seek(time)
    end
    if self.wantPlay and self.state == 'ready' then
        self:start()
    end
    if self.seeking then
        return
    end
    if self.playing then
        self.wall = self.wall + dt * self.speed
    end
    if self.playing or self.needFrame then
        present(self, self:getTime())
    end
    if self.playing and self.control:load(2) == 1 and self.control:load(0) == self.control:load(1) then
        local last = (self.shown or 0) + 1 / math.max(self.fps, 1)
        if self:getTime() >= last then
            self:finished()
        end
    end
end

function Player:finished()
    if self.loop then
        self.looped = (self.looped or 0) + 1
        self:seek(0)
        if self.onLooped then
            self.onLooped()
        end
    else
        self.state, self.playing, self.wantPlay = 'finished', false, false
        self.audioRunning = false
        if self.audio then
            self.audio:pause()
        end
        if self.onFinished then
            self.onFinished()
        end
    end
end

function Player:release()
    if self.audio then
        self.audio:release()
        self.audio = nil
    end
    if self.thread then
        self.thread:stop(200)
        self.thread:destroy()
        self.thread = nil
    end
    if self.image then
        self.image:release()
        self.image = nil
    end
    self.state, self.playing = 'released', false
end

return Player
