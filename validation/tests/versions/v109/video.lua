-- Video playback: FFmpeg decoder, worker thread, frame ring, audio clock. Skipped without FFmpeg.
local Module = {}

local function pump(player, seconds, until_)
    local deadline = katsa.timer.getTime() + seconds
    local last = katsa.timer.getTime()
    while katsa.timer.getTime() < deadline do
        local now = katsa.timer.getTime()
        player:update(now - last)
        last = now
        if until_ and until_() then
            return true
        end
        katsa.timer.sleep(0.004)
    end
    return until_ == nil
end

function Module.run(self)
    local Player = require('source.engine.video.player')
    if not Player.isSupported() then
        print('SKIP video: FFmpeg libraries or worker threads are not available')
        return
    end
    local finished = 0
    local player, message = Player.new({
        path = 'validation/tests/fixtures/video/test.mp4',
        autoplay = true,
        onFinished = function()
            finished = finished + 1
        end,
    })
    self:check(player ~= nil, 'A video player opens the file: ' .. tostring(message))
    if not player then
        return
    end
    pump(player, 5, function()
        return player.state ~= 'loading'
    end)
    self:check(player.width == 160 and player.height == 90, 'The player reports the video size')
    self:check(math.abs(player.duration - 1.5) < 0.1 and player.hasAudio, 'Duration and audio are found')
    pump(player, 1, function()
        return (player.frameCount or 0) > 0
    end)
    local canvas = katsa.graphics.newCanvas(160, 90)
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(canvas)
    katsa.graphics.clear(0, 0, 0, 1)
    katsa.graphics.draw(player.image, 0, 0)
    katsa.graphics.setCanvas()
    katsa.graphics.pop()
    local pixels = canvas:newImageData()
    local r, g, b = pixels:getPixel(80, 45)
    pixels:release()
    canvas:release()
    self:check(r + g + b > 0.05, 'The first frame is on the GPU image')
    local ended = pump(player, 6, function()
        return player.state == 'finished'
    end)
    self:check(ended and finished == 1, 'Playback finishes once and reports it')
    self:check((player.frameCount or 0) >= 20, 'Most of the frames were shown')
    player:seek(0.5)
    pump(player, 2, function()
        return not player.seeking
    end)
    pump(player, 1, function()
        return (player.shown or 0) > 0.3
    end)
    self:check((player.shown or 0) >= 0.3, 'Seeking shows a frame from the new position')
    player:release()
    self:check(player.state == 'released', 'Releasing stops the worker')
    Module.node(self)
end

-- The VideoFrame node on a screen UI: loads, plays through the UI update, draws, reports state.
function Module.node(self)
    local Node = require('source.engine.nodes')
    local Resources = require('source.engine.core.resources')
    local UI = require('source.engine.ui')
    local ui = UI.new(160, 90, Resources.new(require('validation.tests.fixtures.manifest')))
    ui.parent = Node.new('World3D', {})
    local finished = 0
    local video = ui:video({
        width = 160,
        height = 90,
        source = 'validation/tests/fixtures/video/test.mp4',
        playing = true,
        fitMode = 'Stretch',
    }, ui.content)
    video:connect('finished', function()
        finished = finished + 1
    end)
    local canvas = katsa.graphics.newCanvas(160, 90)
    local last, lit = katsa.timer.getTime(), false
    local deadline = katsa.timer.getTime() + 8
    while katsa.timer.getTime() < deadline and finished == 0 do
        local now = katsa.timer.getTime()
        ui:update(now - last, now - last)
        last = now
        katsa.graphics.push('all')
        katsa.graphics.setCanvas({ canvas, stencil = true })
        katsa.graphics.clear(0, 0, 0, 1)
        ui:draw()
        katsa.graphics.setCanvas()
        katsa.graphics.pop()
        if not lit and video.time > 0.3 then
            local pixels = canvas:newImageData()
            local r, g, b = pixels:getPixel(80, 45)
            pixels:release()
            lit = r + g + b > 0.05
        end
        katsa.timer.sleep(0.004)
    end
    self:check(lit, 'A VideoFrame draws the playing video')
    self:check(finished == 1 and video.playing == false, 'A VideoFrame emits finished and stops')
    self:check(math.abs(video.duration - 1.5) < 0.1, 'A VideoFrame reports the duration')
    video:destroy()
    canvas:release()
    ui:release()
end

return Module
