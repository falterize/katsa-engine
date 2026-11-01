-- Rewarded ads, independent of the ad network.
--
--   local Ads = Plugins.require('ads')
--   Ads.configure({ provider = 'admob', rewardedUnit = 'ca-app-pub-xxxx/yyyy' })  -- your key
--   if Ads.isRewardedReady() then
--       Ads.showRewarded(function(result) if result.rewarded then refill() end end)
--   end
--
-- The reward only counts on the machine that must trust it: a multiplayer game should send the
-- request to the server (see the multiplayerCars scene), never let a client grant itself.
--
-- A provider is a table:
--   load(config, done)   -- prefetch; done(ok, message)
--   isReady() -> bool
--   show(config, done)   -- play; done({ rewarded = bool, error = string|nil })
local Ads = {}

local providers = {}
local state = { provider = nil, name = nil, config = {}, loading = false }

function Ads.registerProvider(name, provider)
    assert(
        type(name) == 'string' and type(provider) == 'table',
        'Provider needs a name and a table'
    )
    providers[name] = provider
end

Ads.registerProvider('mock', require('source.plugins.ads.mock'))
Ads.registerProvider('admob', require('source.plugins.ads.admob'))
Ads.registerProvider('unity', require('source.plugins.ads.unity'))

-- config.provider: 'mock' (default), 'admob', 'unity', or any registered name.
-- Network keys live in the config you pass here; nothing is stored in the engine.
function Ads.configure(config)
    config = config or {}
    local name = config.provider or 'mock'
    local provider = assert(providers[name], 'Unknown ad provider: ' .. tostring(name))
    state.provider, state.name, state.config = provider, name, config
    state.loading = false
    return Ads
end

function Ads.getProvider()
    return state.name
end

-- Starts loading an ad. done(ok, message) is optional.
function Ads.load(done)
    if not state.provider then
        Ads.configure({})
    end
    if state.loading then
        return
    end
    state.loading = true
    state.provider.load(state.config, function(ok, message)
        state.loading = false
        if done then
            done(ok, message)
        end
    end)
end

function Ads.isRewardedReady()
    return state.provider ~= nil and state.provider.isReady()
end

-- Plays a rewarded ad. done({ rewarded = bool, error = string|nil }) is always called once.
-- The next ad is prefetched afterwards.
function Ads.showRewarded(done)
    if not state.provider then
        Ads.configure({})
    end
    if not state.provider.isReady() then
        Ads.load()
        if done then
            done({ rewarded = false, error = 'not ready' })
        end
        return false
    end
    state.provider.show(state.config, function(result)
        Ads.load()
        if done then
            done(result)
        end
    end)
    return true
end

-- Call every frame: lets providers that wait on timers or callbacks advance.
function Ads.update(dt)
    local provider = state.provider
    if provider and provider.update then
        provider.update(dt)
    end
end

return Ads
