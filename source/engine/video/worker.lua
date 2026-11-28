-- Decoder thread script (run by katsa.thread through source/engine/video/player.lua). It owns the
-- FFmpeg decoder and fills a ring of RGBA frames in shared memory; the player reads it. Decoded
-- audio goes back as messages. Shared layout (int32 `control`): [0] frames written, [1] frames
-- read, [2] end-of-file flag. Both counters restart at zero on every seek; the player does not
-- touch the ring between sending `seek` and receiving the reply, so the reset cannot race.
local Decoder = require('source.engine.video.decoder')
local SharedArray = require('source.katsa.thread.sharedArray')

Actor.manual = true

local decoder, control, times, frames
local slots, frameBytes = 0, 0
local epoch, atEnd = 0, false

local function sendAudio(pts, pcm, count)
    Actor.send('audio', { epoch = epoch, pts = pts, pcm = pcm, frames = count })
end

Actor.on('open', function(data)
    local opened, message = Decoder.open(data.path, { maxHeight = data.maxHeight })
    if not opened then
        return { error = message }
    end
    decoder = opened
    return {
        width = decoder.width,
        height = decoder.height,
        duration = decoder.duration,
        fps = decoder.fps,
        hasAudio = decoder.hasAudio,
        sampleRate = decoder.sampleRate,
        channels = decoder.channels,
    }
end)

Actor.on('attach', function(data)
    slots, frameBytes = data.slots, data.frameBytes
    control = SharedArray.attach(data.control, 'int32_t', 4)
    times = SharedArray.attach(data.times, 'double', slots)
    frames = SharedArray.attach(data.frames, 'uint8_t', slots * frameBytes)
    return true
end)

Actor.on('seek', function(data)
    epoch = data.epoch
    decoder:seek(data.time)
    atEnd = false
    control:store(2, 0)
    control:store(0, 0)
    control:store(1, 0)
    return epoch
end)

while not Actor.stopped() do
    Actor.poll(0)
    if decoder and frames and not atEnd then
        local written = control:load(0)
        if written - control:load(1) < slots then
            local slot = written % slots
            local pts = decoder:readFrame(frames.data + slot * frameBytes, sendAudio)
            if pts then
                times.data[slot] = pts
                control:store(0, written + 1)
            else
                atEnd = true
                control:store(2, 1)
            end
        else
            Actor.sleep(2)
        end
    else
        Actor.sleep(4)
    end
end
if decoder then
    decoder:close()
end
