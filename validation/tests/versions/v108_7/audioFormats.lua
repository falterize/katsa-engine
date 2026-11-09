-- Audio decoders: WAV, Ogg Vorbis, FLAC (lossless, so it must equal the WAV) and MP3; Opus is
-- refused with a clear message.
local Tests = {}

local DIR = 'validation/tests/fixtures/audio/'

local function load(name)
    return katsa.sound.newSoundData(DIR .. name)
end

function Tests.run(tester)
    local wav = load('tone.wav')
    local flac = load('tone.flac')
    tester:check(
        flac:getSampleCount() == wav:getSampleCount() and flac:getSampleRate() == 44100,
        'FLAC keeps the sample count and rate'
    )
    local same = true
    for i = 0, wav:getSampleCount() - 1 do
        if flac:getSample(i) ~= wav:getSample(i) then
            same = false
            break
        end
    end
    tester:check(same, 'FLAC decodes to exactly the same samples as the WAV')

    local mp3 = load('tone.mp3')
    tester:check(
        mp3:getSampleRate() == 44100 and mp3:getChannelCount() == 1
            and math.abs(mp3:getDuration() - 0.5) < 0.1,
        'MP3 decodes to mono 44.1 kHz of about the right length'
    )
    local function peakOf(data)
        local peak = 0
        for i = 0, data:getSampleCount() - 1 do
            peak = math.max(peak, math.abs(data:getSample(i)))
        end
        return peak
    end
    tester:check(
        math.abs(peakOf(mp3) - peakOf(wav)) < 0.05 * peakOf(wav) + 0.01,
        'MP3 keeps the signal level'
    )

    local ok, message = pcall(load, 'tone.opus')
    tester:check(not ok and tostring(message):find('Opus'), 'Ogg Opus is refused with a clear message')
    tester:check(not pcall(katsa.sound.newSoundData, 'not audio at all, just text'), 'Unknown data is refused')
end

return Tests
