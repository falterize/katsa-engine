-- katsa.audio: sources, listener and effects. Playback state lives here; a driver (OpenAL, or the
-- silent null driver used for servers and tests) turns it into sound.
local State = require('source.katsa.audio.state')

for _, name in ipairs({ 'control', 'source', 'listener', 'effects' }) do
    require('source.katsa.audio.' .. name)
end

return State.Audio
