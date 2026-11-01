-- Silent driver: keeps Source state only. Used on servers, in tests and when no audio device
-- exists.
local Driver = { name = 'null', effectsSupported = true, maxSourceEffects = 4 }

local function noop() end
Driver.createVoice = noop
Driver.destroyVoice = noop
Driver.play = noop
Driver.stop = noop
Driver.pause = noop
Driver.seek = noop
Driver.update = noop
Driver.updateListener = noop
Driver.defineEffect = noop
Driver.removeEffect = noop

return Driver
