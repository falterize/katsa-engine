-- Ads plugin: provider selection, mock rewarded flow, and unavailable native bridges.
return function(T)
    local Ads = require('source.plugins.ads')
    Ads.configure({ provider = 'mock', mockDuration = 0.5 })
    T.check(not Ads.isRewardedReady(), 'ads: nothing is ready before loading')
    local result = {}
    T.check(not Ads.showRewarded(function(r) result.early = r end) and result.early.error == 'not ready',
        'ads: showing before load reports not ready')
    T.check(Ads.isRewardedReady(), 'ads: a failed show starts loading')
    T.check(Ads.showRewarded(function(r) result.done = r end), 'ads: a ready ad starts')
    Ads.update(0.2)
    T.check(result.done == nil, 'ads: reward waits for the ad to finish')
    Ads.update(0.4)
    T.check(result.done and result.done.rewarded == true, 'ads: finished ad rewards')
    T.check(Ads.isRewardedReady(), 'ads: next ad is prefetched')
    Ads.configure({ provider = 'mock', mockDuration = 0.1, mockSkip = true })
    Ads.load()
    Ads.showRewarded(function(r) result.skipped = r end)
    Ads.update(0.2)
    T.check(result.skipped and result.skipped.rewarded == false, 'ads: skipping gives no reward')
    Ads.configure({ provider = 'admob', rewardedUnit = 'ca-app-pub-test/1' })
    local message
    Ads.load(function(_, text) message = text end)
    T.check(not Ads.isRewardedReady() and message and message:find('unavailable'),
        'ads: AdMob without a bridge reports it')
    T.check(not pcall(Ads.configure, { provider = 'nope' }), 'ads: unknown provider is rejected')
end
