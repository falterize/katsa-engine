-- Google AdMob (the most widely used mobile ad network).
-- AdMob is a mobile SDK, so it is reached through a native bridge exposed by the Android/iOS
-- host as `katsa.platform.ads`:
--   bridge.loadRewarded(unitId, function(ok, message) end)
--   bridge.isRewardedReady() -> bool
--   bridge.showRewarded(function(rewarded, errorMessage) end)
-- config: { provider = 'admob', rewardedUnit = 'ca-app-pub-.../...' }
-- Test unit ids are published by Google; use them until you have your own key.
local AdMob = {}

local function bridge()
    local platform = katsa and katsa.platform
    return platform and platform.ads
end

function AdMob.load(config, done)
    local native = bridge()
    if not native then
        return done(false, 'AdMob bridge unavailable on this platform')
    end
    if not config.rewardedUnit then
        return done(false, 'config.rewardedUnit is required')
    end
    native.loadRewarded(config.rewardedUnit, done)
end

function AdMob.isReady()
    local native = bridge()
    return native ~= nil and native.isRewardedReady() == true
end

function AdMob.show(_, done)
    bridge().showRewarded(function(rewarded, message)
        done({ rewarded = rewarded == true, error = message })
    end)
end

return AdMob
