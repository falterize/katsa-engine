-- Pull-based media decoder on the FFmpeg binding: opens a file, decodes the first video stream
-- into RGBA frames and the first audio stream into interleaved 16-bit PCM. It has no engine
-- dependency, so the same module runs on the main thread (tests) and in the decoder worker.
--
--   local decoder = Decoder.open(path)           -- or nil, message
--   decoder.width, decoder.height, decoder.duration, decoder.hasAudio, decoder.sampleRate
--   local pts = decoder:readFrame(rgbaPointer, function(pts, pcm, frames) ... end)
--   decoder:seek(seconds)
--   decoder:close()
--
-- `readFrame` fills `rgbaPointer` (width * height * 4 bytes) with the next video frame and returns
-- its time in seconds, or nil at the end of the file. Audio decoded on the way goes to the callback
-- (pcm is a Lua string of `frames` interleaved int16 frames, `channels` per frame).
local ffi = require('ffi')
local Libav = require('source.engine.video.libav')

local Decoder = {}
Decoder.__index = Decoder

local MIN_TS = -9223372036854775807LL - 1LL

local function seconds(value, base)
    return tonumber(value) * base.num / base.den
end

-- Opens the decoder for `stream` of `format`; nil when there is no usable decoder.
local function openCodec(lib, stream)
    local parameters = stream.codecpar
    local codec = lib.codec.avcodec_find_decoder(parameters.codec_id)
    if codec == nil then
        return nil
    end
    local context = lib.codec.avcodec_alloc_context3(codec)
    if lib.codec.avcodec_parameters_to_context(context, parameters) < 0
        or lib.codec.avcodec_open2(context, codec, nil) < 0 then
        local holder = ffi.new('void*[1]', context)
        lib.codec.avcodec_free_context(holder)
        return nil
    end
    return context
end

-- options.maxHeight (optional) scales larger pictures down while decoding (width follows).
function Decoder.open(path, options)
    local lib, message = Libav.load()
    if not lib then
        return nil, message
    end
    local holder = ffi.new('AVFormatContext*[1]')
    local code = lib.format.avformat_open_input(holder, path, nil, nil)
    if code < 0 then
        return nil, ('Cannot open %s: %s'):format(path, Libav.describe(code))
    end
    local format = holder[0]
    if lib.format.avformat_find_stream_info(format, nil) < 0 then
        lib.format.avformat_close_input(holder)
        return nil, 'No stream information in ' .. path
    end
    local self = setmetatable({
        lib = lib,
        format = format,
        holder = holder,
        packet = ffi.gc(lib.codec.av_packet_alloc(), function(pointer)
            lib.codec.av_packet_free(ffi.new('AVPacket*[1]', pointer))
        end),
        frame = lib.util.av_frame_alloc(),
        lastPts = 0,
    }, Decoder)
    self.frameType = ffi.typeof(lib.frameType)
    for index = 0, format.nb_streams - 1 do
        local stream = format.streams[index]
        local kind = stream.codecpar.codec_type
        if kind == Libav.VIDEO and not self.video and stream.codecpar.width > 0 then
            self.video = { index = index, stream = stream, base = stream.time_base }
        elseif kind == Libav.AUDIO and not self.audio then
            self.audio = { index = index, stream = stream, base = stream.time_base }
        end
    end
    if not self.video then
        self:close()
        return nil, 'No video stream in ' .. path
    end
    self.video.context = openCodec(lib, self.video.stream)
    if not self.video.context then
        self:close()
        return nil, 'No decoder for the video of ' .. path
    end
    if self.audio then
        self.audio.context = openCodec(lib, self.audio.stream)
        if not self.audio.context then
            self.audio = nil -- play the picture without sound
        end
    end
    local parameters = self.video.stream.codecpar
    self.width, self.height = parameters.width, parameters.height
    local limit = options and options.maxHeight or 0
    if limit > 0 and self.height > limit then
        self.width = math.max(2, math.floor(self.width * limit / self.height / 2 + 0.5) * 2)
        self.height = limit
    end
    -- Both streams count from the container's start time.
    local start = format.start_time ~= Libav.NOPTS and tonumber(format.start_time) / 1e6 or 0
    self.origin = start
    self.duration = format.duration ~= Libav.NOPTS and tonumber(format.duration) / 1e6 or 0
    local frames = tonumber(self.video.stream.nb_frames)
    self.fps = frames > 0 and self.duration > 0 and frames / self.duration or 30
    self.hasAudio = self.audio ~= nil
    if self.audio then
        local ok, rate, channels = pcall(function()
            local value = ffi.new('int64_t[1]')
            lib.util.av_opt_get_int(self.audio.context, 'ar', 1, value)
            local layout = ffi.new('AVChannelLayout[1]')
            lib.util.av_opt_get_chlayout(self.audio.context, 'ch_layout', 1, layout)
            return tonumber(value[0]), layout[0].nb_channels
        end)
        self.sampleRate = ok and rate or 44100
        self.channels = ok and channels > 1 and 2 or 1
    end
    return self
end

-- Frame time in seconds, or the running estimate when the file has no timestamp for it.
local function frameTime(self, track, pts)
    if pts ~= Libav.NOPTS then
        return seconds(pts, track.base) - self.origin
    end
    return self.lastPts + 1 / self.fps
end

local function toRgba(self, frame, target)
    local lib = self.lib
    local width, height, format = frame.width, frame.height, frame.format
    local key = width .. 'x' .. height .. ':' .. format
    if self.scaleKey ~= key then
        if self.scaler then
            lib.scale.sws_freeContext(self.scaler)
        end
        self.scaler = lib.scale.sws_getContext(
            width, height, format, self.width, self.height, Libav.PIX_FMT_RGBA, 2, nil, nil, nil
        )
        self.scaleKey = key
    end
    if self.scaler == nil then
        return false
    end
    local destination = ffi.new('uint8_t*[1]', target)
    local stride = ffi.new('int[1]', self.width * 4)
    lib.scale.sws_scale(
        self.scaler,
        ffi.cast('const uint8_t* const*', frame.data),
        frame.linesize,
        0,
        height,
        destination,
        stride
    )
    return true
end

-- Converts a decoded audio frame to interleaved int16 and hands it to `sink`.
local function emitAudio(self, frame, sink)
    local lib = self.lib
    local audio = self.audio
    local channels, rate = self.channels, self.sampleRate
    if not audio.resampler then
        local input = ffi.new('AVChannelLayout[1]')
        lib.util.av_opt_get_chlayout(audio.context, 'ch_layout', 1, input)
        local output = ffi.new('AVChannelLayout[1]')
        lib.util.av_channel_layout_default(output, channels)
        local holder = ffi.new('SwrContext*[1]')
        local code = lib.resample.swr_alloc_set_opts2(
            holder, output, Libav.SAMPLE_FMT_S16, rate, input, frame.format, rate, 0, nil
        )
        if code < 0 or lib.resample.swr_init(holder[0]) < 0 then
            self.audio = nil
            self.hasAudio = false
            return
        end
        audio.resampler = holder[0]
    end
    local capacity = frame.nb_samples + 2048
    local buffer = ffi.new('uint8_t[?]', capacity * channels * 2)
    local out = ffi.new('uint8_t*[1]', buffer)
    local count = lib.resample.swr_convert(
        audio.resampler, out, capacity, ffi.cast('const uint8_t**', frame.extended_data), frame.nb_samples
    )
    if count > 0 then
        local pts = frameTime(self, audio, frame.pts)
        sink(pts, ffi.string(buffer, count * channels * 2), count)
    end
end

-- Decodes whatever the audio decoder has ready.
local function drainAudio(self, sink)
    local lib = self.lib
    local frame = ffi.cast(self.frameType, self.frame)
    while self.audio do
        local code = lib.codec.avcodec_receive_frame(self.audio.context, self.frame)
        if code < 0 then
            return
        end
        if sink then
            emitAudio(self, frame, sink)
        end
        lib.util.av_frame_unref(self.frame)
    end
end

-- Reads packets until the video decoder yields a frame; false when the file is over.
local function feed(self, audioSink)
    local lib = self.lib
    local packet = self.packet
    while true do
        local code = lib.format.av_read_frame(self.format, packet)
        if code < 0 then
            if not self.draining then
                self.draining = true
                lib.codec.avcodec_send_packet(self.video.context, nil)
                if self.audio then
                    lib.codec.avcodec_send_packet(self.audio.context, nil)
                    drainAudio(self, audioSink)
                end
                return true
            end
            return false
        end
        local index = packet.stream_index
        if index == self.video.index then
            lib.codec.avcodec_send_packet(self.video.context, packet)
            lib.codec.av_packet_unref(packet)
            return true
        elseif self.audio and index == self.audio.index then
            lib.codec.avcodec_send_packet(self.audio.context, packet)
            lib.codec.av_packet_unref(packet)
            drainAudio(self, audioSink)
        else
            lib.codec.av_packet_unref(packet)
        end
    end
end

function Decoder:readFrame(target, audioSink)
    local lib = self.lib
    local frame = ffi.cast(self.frameType, self.frame)
    while true do
        local code = lib.codec.avcodec_receive_frame(self.video.context, self.frame)
        if code == 0 then
            local pts = frameTime(self, self.video, frame.pts)
            local ok = toRgba(self, frame, target)
            lib.util.av_frame_unref(self.frame)
            if ok then
                self.lastPts = pts
                return pts
            end
        elseif code == Libav.AGAIN then
            if not feed(self, audioSink) then
                return nil
            end
        else
            return nil -- end of stream (or an unrecoverable decode error)
        end
    end
end

-- Jumps to the keyframe at or before `time`; the next frames may be a little earlier than `time`.
function Decoder:seek(time)
    local lib = self.lib
    local target = math.floor((math.max(0, time) + self.origin) * 1e6)
    lib.format.avformat_seek_file(self.format, -1, MIN_TS, target, target, 0)
    lib.codec.avcodec_flush_buffers(self.video.context)
    if self.audio then
        lib.codec.avcodec_flush_buffers(self.audio.context)
    end
    self.draining = false
    self.lastPts = math.max(0, time)
end

function Decoder:close()
    local lib = self.lib
    if self.scaler then
        lib.scale.sws_freeContext(self.scaler)
        self.scaler = nil
    end
    for _, track in ipairs({ self.video or {}, self.audio or {} }) do
        if track.resampler then
            lib.resample.swr_free(ffi.new('SwrContext*[1]', track.resampler))
            track.resampler = nil
        end
        if track.context then
            lib.codec.avcodec_free_context(ffi.new('void*[1]', track.context))
            track.context = nil
        end
    end
    if self.frame then
        lib.util.av_frame_free(ffi.new('void*[1]', self.frame))
        self.frame = nil
    end
    if self.format then
        lib.format.avformat_close_input(self.holder)
        self.format = nil
    end
end

return Decoder
