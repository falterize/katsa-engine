local Store = require('source.engine.persistence.store')
local Settings = require('source.engine.persistence.settings')
local History = require('source.engine.debug.statistics.history')
local FrameTimes = require('source.engine.debug.statistics.frameTimes')
local Export = require('source.engine.debug.statistics.export')
local Application = require('source.game.runtime.application')

local Tests = {}

function Tests.statistics(tester)
    local history = History.new(3, 1, 'rate')
    history:sample(0.01, 100)
    history:sample(0.11, 10)
    local summary = history:summary()
    tester:check(
        math.abs(summary.mean - 2 / 0.11) < 0.00001,
        'FPS uses frames divided by elapsed time instead of mean instantaneous FPS'
    )
    tester:check(
        history:get(1).mean == summary.mean and summary.low == 10 and summary.high == 100,
        'FPS bars and window mean use the same rate while preserving spikes'
    )
    history:sample(1.12, 50)
    tester:check(
        math.abs(history:summary().mean - 3 / 0.13) < 0.00001,
        'Rate windows combine elapsed time across buckets'
    )
    tester:check(history:summary(0.5, nil, 1.12).mean == 50, 'Rate windows exclude expired buckets')
    tester:check(
        not pcall(history.sample, history, 1.13, 0),
        'Zero FPS cannot create an invalid duration'
    )
    local ordinary = History.new()
    ordinary:sample(0, 100)
    ordinary:sample(0.1, 10)
    tester:check(ordinary:summary().mean == 55, 'Non-rate metrics retain arithmetic means')
    local csv = Export.build({ { id = 'fps', label = 'FPS' } }, { fps = history }, {
        time = 1.12,
        seconds = 5,
        scope = 'all',
    })
    tester:check(
        csv:find('aggregation,duration_seconds', 1, true) and csv:find('events/seconds', 1, true),
        'CSV declares corrected FPS aggregation'
    )
    local frames = FrameTimes.new(100)
    for _ = 1, 99 do
        frames:add(0.01)
    end
    frames:add(0.1)
    local result = frames:summary()
    tester:check(
        math.abs(result.fps - 100 / 1.09) < 0.00001,
        'Benchmark throughput measures frames per elapsed second'
    )
    tester:check(
        result.p95Milliseconds == 10
            and result.p99Milliseconds == 10
            and result.worstMilliseconds == 100
            and result.framesOver60HzBudget == 1,
        'Frame reports expose tail latency and isolated long frames'
    )
    frames:add(0.02)
    tester:check(
        frames.count == 100 and frames:summary().worstMilliseconds == 100,
        'Frame storage stays bounded after wrapping'
    )
end

function Tests.saves(tester)
    local store =
        Store.new('validation-v1068', { defaults = { score = 0, sound = { volume = 0.5 } } })
    assert(store:remove('progress'))
    local data, metadata = store:read('progress')
    tester:check(
        data.score == 0 and metadata.status == 'new',
        'Missing save returns independent defaults'
    )
    data.sound.volume = 0
    tester:check(
        store:read('progress').sound.volume == 0.5,
        'Read defaults are never shared with callers'
    )
    tester:check(
        not pcall(Store.new, '../escape') and not pcall(store.paths, store, '../escape'),
        'Save namespaces and slots reject path traversal'
    )
    local committed, failure = store:write('progress', { score = 10 })
    tester:check(committed, 'Progress commits to a verified generation: ' .. tostring(failure))
    tester:check(
        store:write('progress', { score = 20 }),
        'A second generation retains the previous save'
    )
    data, metadata = store:read('progress')
    tester:check(
        data.score == 20 and metadata.generation == 2 and metadata.status == 'loaded',
        'The newest valid generation loads with nested defaults'
    )
    local fs = {}
    for key, value in pairs(katsa.filesystem) do
        fs[key] = value
    end
    fs.rename = function()
        return nil, 'Injected commit failure'
    end
    local failing = Store.new('validation-v1068', { filesystem = fs })
    tester:check(
        not failing:write('progress', { score = 30 }),
        'Commit failure is returned to the caller'
    )
    tester:check(
        store:read('progress').score == 20,
        'Interrupted commit preserves the current generation'
    )
    tester:check(
        store:write('progress', { score = 30 }),
        'A subsequent write recovers after interrupted commit'
    )
    local current = store:latest('progress')
    assert(katsa.filesystem.write(current.path, '{broken'))
    data, metadata = store:read('progress')
    tester:check(
        data.score == 20 and metadata.status == 'recovered',
        'Damaged newest file falls back to its sibling'
    )
    local a, b = store:paths('progress')
    assert(katsa.filesystem.write(a, 'bad'))
    assert(katsa.filesystem.write(b, 'bad'))
    tester:check(
        not store:read('progress') and not store:write('progress', {}),
        'Two damaged files are reported and never silently overwritten'
    )
    assert(store:remove('progress'))
    assert(store:write('progress', { points = 7 }))
    local migrated = Store.new('validation-v1068', {
        version = 3,
        defaults = { volume = 1 },
        migrations = {
            [1] = function(value)
                value.score, value.points = value.points, nil
                return value
            end,
            [2] = function(value)
                value.level = 1
                return value
            end,
        },
    })
    data, metadata = migrated:read('progress')
    tester:check(
        data.score == 7 and data.level == 1 and data.volume == 1 and metadata.migrated,
        'Versioned migrations run in order before merging defaults'
    )
    assert(migrated:write('progress', data))
    tester:check(
        not store:read('progress') and not store:write('progress', {}),
        'Older game versions cannot load or overwrite a newer save schema'
    )
    local small = Store.new('validation-size-v1068', { maxBytes = 32 })
    tester:check(
        not small:write('progress', { text = string.rep('x', 64) }),
        'Oversized saves fail before commit'
    )
    tester:check(
        not migrated:write('progress', { invalid = function() end }),
        'Non-data values cannot enter save files'
    )
    assert(store:remove('settings'))
    local preferences = assert(Settings.new('validation-v1068', { defaults = { volume = 0.8 } }))
    preferences:set('volume', 0.25)
    tester:check(
        preferences.dirty and preferences:save() and not preferences.dirty,
        'Settings track edits and clear dirty state only after a successful save'
    )
    local loaded = assert(Settings.new('validation-v1068'))
    tester:check(
        loaded:get('volume') == 0.25,
        'Settings persist across independent service instances'
    )
    preferences:set('volume', 0.5)
    preferences.store.fs = fs
    tester:check(
        not preferences:save() and preferences.dirty,
        'Settings remain dirty after failed commit'
    )
    assert(store:remove('progress'))
    assert(store:remove('settings'))
end

function Tests.starter(tester)
    local journalCount = #tester.manager.journal.entries
    local path = 'starterGame'
    local scene = assert(tester.manager:switch(Application.new, path))
    tester:check(
        scene.settings.runtime == 'standalone' and scene.world.byName.Cube,
        'Starter scene loads its own content through the standalone host'
    )
    tester:check(
        not scene.workspace and not scene.navigation and not scene.demo,
        'Standalone games do not instantiate example navigation or tools'
    )
    for _ = 1, 10 do
        tester.manager:update(1 / 60)
    end
    scene:draw()
    local background = scene.statistics.panel.histories.fps
    tester:check(
        background and background:summary().samples == 1 and #scene.statistics.panel.rows == 0,
        'Hidden Stats retains lightweight frame history without constructing metric rows'
    )
    scene.showStats = true
    scene:draw()
    tester:check(
        scene.statistics.panel.histories.fps.aggregation == 'rate',
        'Standalone Stats uses the shared corrected FPS history'
    )
    tester:check(
        scene.statistics.panel.histories.fps == background and background:summary().samples == 2,
        'Opening Stats preserves the recorded hidden-overlay history'
    )
    local graphicsStats, queries = katsa.graphics.getStats, 0
    katsa.graphics.getStats = function(...)
        queries = queries + 1
        return graphicsStats(...)
    end
    scene.statistics.panel.nextRefresh = tester.manager.frameTime
    local sampled, samplingError = pcall(function()
        for _ = 1, 10 do
            tester.manager:update(0.01)
            scene:draw()
        end
    end)
    katsa.graphics.getStats = graphicsStats
    assert(sampled, samplingError)
    tester:check(
        queries == 1,
        'Graphics counters refresh at UI cadence while FPS samples every frame'
    )
    local retired = setmetatable({ scene }, { __mode = 'v' })
    local resources = scene.resources
    local shared = scene.data:scope('validation-scene-transfer-v1068')
    assert(shared:save('transfer', { value = 73 }))
    local menu = assert(tester.manager:switch(Application.new, 'menu'))
    tester:check(
        menu.data == tester.manager.data
            and menu.data:scope('validation-scene-transfer-v1068'):load('transfer').value == 73,
        'A different interface scene reads data saved by the standalone gameplay scene'
    )
    assert(shared:remove('transfer'))
    tester:check(resources.released, 'Standalone scene teardown releases its resource scope')
    tester:check(
        #tester.manager.journal.entries == journalCount,
        'Standalone assets resolve without missing-resource journal entries'
    )
    scene, resources = nil, nil
    collectgarbage('collect')
    collectgarbage('collect')
    tester:check(
        retired[1] == nil,
        'Scene replacement retires compiled references to the old instance'
    )
end

function Tests.run(tester)
    require('source.tests.versions.v106_8.framePacing').run(tester)
    Tests.statistics(tester)
    Tests.saves(tester)
    require('source.tests.versions.v106_8.sharedData').run(tester)
    require('source.tests.versions.v106_8.dataFolders').run(tester)
    Tests.starter(tester)
end

function Tests.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED foundation ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable({ manager = manager, count = 0 }, { __index = Tests })
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS foundation', label)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    Tests.run(self)
    print('PASSED ' .. self.count .. ' foundation checks')
    katsa.event.quit()
end

return Tests
