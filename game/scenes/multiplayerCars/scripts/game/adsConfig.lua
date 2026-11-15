-- Rewarded-ad setup. Put your own ids here; nothing else in the scene needs to change.
--
--   AdMob (default on Android/iOS):  https://admob.google.com  -> create a Rewarded ad unit
--   Unity Ads: set provider = 'unity' and fill gameId / rewardedUnit.
--
-- Until real ids are filled in, desktop builds use the 'mock' provider, which plays a short
-- fake ad so the whole flow can be tested. The ids below are Google's public TEST ids.
local Config = {
    -- 'auto' picks admob on mobile and mock elsewhere. Force a provider by name if you like.
    provider = 'auto',
    admob = {
        rewardedUnit = 'ca-app-pub-3940256099942544/5224354917', -- Google test rewarded unit
    },
    unity = {
        gameId = 'YOUR_UNITY_GAME_ID',
        rewardedUnit = 'Rewarded_Android',
    },
    mock = { mockDuration = 2.0 },
}

function Config.resolve()
    local provider = Config.provider
    if provider == 'auto' then
        local os = katsa.system.getOS and katsa.system.getOS() or ''
        provider = (os == 'Android' or os == 'iOS') and 'admob' or 'mock'
    end
    local settings = { provider = provider }
    for key, value in pairs(Config[provider] or {}) do
        settings[key] = value
    end
    return settings
end

return Config
