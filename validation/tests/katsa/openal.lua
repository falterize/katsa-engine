-- OpenAL driver against OpenAL Soft's "null" backend (no sound card needed).
return function(T)
    local ffi = require('ffi')
    if jit.os == 'Windows' then
        return T.skip('openal: null backend setup is POSIX only')
    end
    ffi.cdef('int setenv(const char* name, const char* value, int overwrite);')
    ffi.C.setenv('ALSOFT_DRIVERS', 'null', 1)
    local Driver = require('source.katsa.audio.openal')
    local driver, reason = Driver.open()
    if not driver then
        return T.skip('openal: unavailable (' .. tostring(reason) .. ')')
    end
    local Audio = require('source.katsa.audio')
    local Sound = require('source.katsa.sound')
    Audio.setDriver(driver)

    local data = Sound.newSoundData(44100, 44100, 16, 1)
    local source = Audio.newSource(data, 'static')
    T.check(not driver.isPlaying(source), 'a new voice is not playing')
    source:play()
    T.check(driver.isPlaying(source), 'play starts the OpenAL voice')
    source:pause()
    T.check(not driver.isPlaying(source) and source:isPaused(), 'pause stops the voice')
    source:play()
    source:stop()
    T.check(not driver.isPlaying(source), 'stop ends playback')

    source:setVolume(0.5)
    source:setPosition(1, 2, 3)
    Audio.setPosition(0, 0, 0)
    Audio.setDistanceModel('linear')
    Audio.setDopplerScale(2)
    T.check(source:getVolume() == 0.5 and Audio.getDopplerScale() == 2,
        'properties reach the driver')

    local copy = source:clone()
    copy:play()
    T.check(driver.isPlaying(copy) and not driver.isPlaying(source), 'clones play independently')
    copy:release()

    -- EFX: effects become auxiliary slots, filters attach to the dry path.
    T.check(driver.effectsSupported and driver.maxSourceEffects >= 1, 'OpenAL reports EFX support')
    local fx = Audio.newSource(data, 'static')
    for name, settings in pairs({
        reverb = { type = 'reverb', decaytime = 2.5, gain = 0.4, volume = 1 },
        echo = { type = 'echo', delay = 0.1, feedback = 0.5, volume = 1 },
        chorus = { type = 'chorus', waveform = 'triangle', rate = 2, volume = 1 },
        distortion = { type = 'distortion', edge = 0.4, gain = 0.2, volume = 1 },
    }) do
        local ok, err = pcall(Audio.setEffect, name, settings)
        T.check(ok, name .. ' effect is accepted by OpenAL ' .. tostring(err))
        T.check(fx:setEffect(name, true), name .. ' attaches to a source')
    end
    T.check(fx:setFilter({ type = 'lowpass', volume = 1, highgain = 0.1 }), 'low-pass filter applies')
    fx:setFilter(nil)
    for _, name in ipairs({ 'reverb', 'echo', 'chorus', 'distortion' }) do
        Audio.setEffect(name, false)
    end
    fx:play()
    T.check(driver.isPlaying(fx), 'a source with effects plays')
    fx:release()
    source:release()
    Audio.setDriver(require('source.katsa.audio.nullDriver'))
    driver.close()
end
