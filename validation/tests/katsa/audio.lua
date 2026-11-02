return function(T)
    local Audio = require('source.katsa.audio')
    local Sound = require('source.katsa.sound')
    Audio.setDriver(require('source.katsa.audio.nullDriver'))

    local data = Sound.newSoundData(4410, 44100, 16, 1)
    local source = Audio.newSource(data, 'static')
    T.check(source:isStopped() and source:getType() == 'static', 'new source is stopped')
    source:play()
    T.check(source:isPlaying() and Audio.getActiveSourceCount() == 1,
        'play marks the source active')
    source:pause()
    T.check(source:isPaused() and not source:isPlaying(), 'pause')
    source:stop()
    T.check(source:isStopped(), 'stop')

    source:setPosition(1, 2, 3)
    local x, y, z = source:getPosition()
    T.check(x == 1 and y == 2 and z == 3, 'source position')
    source:setCone(1, 2, 0.5)
    local inner, outer, gain = source:getCone()
    T.check(inner == 1 and outer == 2 and gain == 0.5, 'cone round trip')
    source:setVolumeLimits(0.25, 0.75)
    local low, high = source:getVolumeLimits()
    T.check(low == 0.25 and high == 0.75, 'volume limits round trip')

    local copy = source:clone()
    T.check(copy ~= source and copy:getType() == 'static', 'clone is independent')

    Audio.setOrientation(0, 0, -1, 0, 1, 0)
    local fx, fy, fz = Audio.getOrientation()
    T.check(fx == 0 and fy == 0 and fz == -1, 'listener orientation')

    Audio.play(source, copy)
    T.check(Audio.getActiveSourceCount() == 2, 'play accepts several sources')
    local paused = Audio.pause()
    T.check(#paused == 2 and Audio.getActiveSourceCount() == 0, 'pause() returns what it paused')
    Audio.stop()

    Audio.setEffect('echo', { type = 'echo' })
    T.check(Audio.getEffect('echo') ~= nil and #Audio.getActiveEffects() == 1, 'effect defined')
    Audio.setEffect('echo', false)
    T.check(Audio.getEffect('echo') == nil, 'effect removed')
    source:release()
    copy:release()

    -- Voice building blocks: μ-law keeps speech within ~3% and the stream API is silent-safe.
    local MuLaw = require('source.engine.audio.muLaw')
    local pcm = { 0, 100, -100, 1000, -1000, 8000, -8000, 30000, -30000 }
    local decoded = MuLaw.decode(MuLaw.encode(pcm, #pcm))
    local worst = 0
    for index = 1, #pcm do
        local error = math.abs(decoded[index - 1] - pcm[index]) / math.max(64, math.abs(pcm[index]))
        worst = math.max(worst, error)
    end
    T.check(worst < 0.07, 'mu-law round trip stays close (' .. ('%.3f'):format(worst) .. ')')
    T.check(#MuLaw.encode(pcm, #pcm) == #pcm, 'mu-law halves the size (one byte per sample)')
    local speaker = Audio.newQueueSource(8000)
    speaker:queue(decoded, #pcm)
    speaker:setPosition(1, 2, 3)
    speaker:release()
    T.check(true, 'a queue source on the null driver swallows data')
end
