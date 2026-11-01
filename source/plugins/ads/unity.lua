-- Unity Ads: same bridge shape as AdMob, exposed as `katsa.platform.unityAds`.
-- config: { provider = 'unity', gameId = '...', rewardedUnit = 'Rewarded_Android' }
local Unity = {}

local function bridge()
    local platform = katsa and katsa.platform
    return platform and platform.unityAds
end

function Unity.load(config, done)
    local native = bridge()
    if not native then
        return done(false, 'Unity Ads bridge unavailable on this platform')
    end
    native.load(config.gameId, config.rewardedUnit, done)
end

function Unity.isReady()
    local native = bridge()
    return native ~= nil and native.isReady() == true
end

function Unity.show(_, done)
    bridge().show(function(rewarded, message)
        done({ rewarded = rewarded == true, error = message })
    end)
end

return Unity
