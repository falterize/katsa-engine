local History = require('source.engine.debug.statistics.history')
local Game = require('source.game.runtime.game')
local World = require('source.engine.world.world')
local Manager = require('source.engine.core.sceneManager')
local Time = require('source.engine.core.time')

local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED v106 ' .. tostring(message))
        os.exit(1)
    end
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    return setmetatable({ manager = manager, count = 0 }, Tests)
end

function Tests:update() end

function Tests:check(value, description)
    assert(value, description)
    self.count = self.count + 1
    print('PASS v106', description)
end

function Tests:history()
    local h = History.new(3, 1)
    h:sample(0, 10)
    h:sample(0.5, 30)
    local first = h:summary(30)
    self:check(
        first.mean == 20 and first.low == 10 and first.high == 30,
        'Bucket aggregates preserve exact sample means and spikes'
    )
    h:sample(1, 50)
    self:check(h:summary(30).mean == 30, 'Window mean weights samples rather than bucket count')
    h:sample(2, -5)
    h:sample(3, -10)
    self:check(
        h.count == 3 and h:get(1).last == 50 and h:get(3).last == -10,
        'Ring overwrites oldest bucket in chronological order'
    )
    self:check(h:summary(0.5).mean == -10, 'Recent window excludes old buckets')
    local buckets = { h.buckets[1], h.buckets[2], h.buckets[3] }
    for i = 4, 100 do
        h:sample(i, i)
    end
    self:check(
        h.buckets[1] == buckets[1] and h.buckets[2] == buckets[2] and h.buckets[3] == buckets[3],
        'Steady-state sampling reuses bounded bucket storage'
    )
    self:check(not pcall(h.sample, h, 99, 0), 'Backwards sample time is rejected')
    self:check(not pcall(h.sample, h, 101, 0 / 0), 'NaN values are rejected')
    self:check(not pcall(History.new, 0), 'Invalid history capacity is rejected')
    h:sample(1000, 0)
    self:check(
        h:summary(5).count == 1 and h:summary(5).mean == 0,
        'Long recording gaps do not invent intermediate data'
    )
end

function Tests:scenes()
    local resources = self.manager.resources:scope()
    local world = World.new(resources, nil, { physics = { backend = 'oimo' } })
    self:check(
        world.physics.backendName == 'oimo',
        'World creation accepts explicit physics settings'
    )
    self:check(
        not pcall(world.createPhysics, world, { backend = 'jolt' }),
        'Configured world cannot silently replace a live solver'
    )
    world:release()
    resources:release()
    self:check(
        not pcall(Game.new, self.manager, 'physics', { physicsBackend = 'invalid' }),
        'Scene validates an unknown backend before loading resources'
    )
    for _, backend in ipairs({ 'oimo', 'jolt' }) do
        local scene = assert(self.manager:switch(Game.new, 'animationPhysicsLab', {
            physicsBackend = backend,
            physics = { workerThreads = 0 },
        }))
        self:check(
            scene.physics.backendName == backend and scene.world.physics == scene.physics,
            'Scene selection overrides the global default: ' .. backend
        )
        local panel = scene.statistics.panel
        self.manager:update(1 / 60)
        self.manager:draw()
        self:check(
            #panel.rows == 0 and panel.histories.fps and not panel.histories['physics.steps'],
            'Hidden Stats keeps only lightweight histories and no allocated rows: ' .. backend
        )
        scene.showStats = true
        for _ = 1, 40 do
            self.manager:update(1 / 60)
            self.manager:draw()
        end
        self:check(
            panel.header.text:find('Physics: ' .. backend, 1, true) ~= nil,
            'Stats reports the actual selected solver: ' .. backend
        )
        self:check(
            #panel.rows == #panel.definitions and #panel.rows > 60,
            'Every numeric metric has its own clickable row: ' .. backend
        )
        for index, definition in ipairs(panel.definitions) do
            panel.rows[index]:press()
            assert(
                panel.selected == index and panel.chart._history == panel.histories[definition.id]
            )
            if panel.histories[definition.id].count == 0 then
                assert(panel.summary.text:find('No recorded samples', 1, true))
            end
            self.manager:draw()
        end
        self:check(panel.popup.visible, 'Every metric opens and draws its own history: ' .. backend)
        panel:select(1)
        panel.seconds = 5
        panel:refreshChart()
        self:check(
            panel.chart._seconds == 5 and panel.summary.text:find('mean (5s)', 1, true),
            'Chart supports recent and retained average windows: ' .. backend
        )
        local history = panel.histories.fps
        local revision = history.revision
        scene.showStats = false
        self.manager:update(1 / 60)
        self.manager:draw()
        self:check(
            history.revision > revision and not panel.popup.visible,
            'Closing Stats retains frame diagnostics and hides its chart: ' .. backend
        )
        scene.showStats = true
        self.manager:update(1 / 60)
        self.manager:draw()
        local row = panel.rows[1]
        scene.ui:scrollBy(panel.scroll, 70)
        scene.ui:layout()
        local x, y =
            scene.ui.offsetX + (row._x + 30) * scene.ui.scale,
            scene.ui.offsetY + (row._y + 12) * scene.ui.scale
        self:check(
            scene.ui:hit(x, y) == row,
            'Numeric row hit testing follows scrolled DPI layout: ' .. backend
        )
        scene.input:press('stats-test', x, y)
        scene.input:release('stats-test', x, y)
        self:check(
            panel.selected == 1 and panel.popup.visible,
            'Normal pointer routing opens the selected chart: ' .. backend
        )
        panel:close()
        scene.input:press('stats-drag', x, y)
        scene.input:move('stats-drag', x, y - 40, 0, -40)
        scene.input:release('stats-drag', x, y - 40)
        self:check(
            not panel.popup.visible and panel.scroll.scrollY > 70,
            'Dragging a numeric row scrolls without opening a chart: ' .. backend
        )
        local custom = scene.ui:container(
            { size = { 0, 10, 0, 10 }, canvasSize = { 0, 10, 0, 10 } },
            scene.ui.content
        )
        scene.ui:layout()
        local revision = scene.ui.revision
        custom.canvasSize[2] = 20
        scene.ui:layout()
        self:check(
            scene.ui.revision > revision,
            'Custom non-scroll canvas values retain mutable snapshot tracking: ' .. backend
        )
        panel:select(1)
    end
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:history()
    local probe = setmetatable({
        frameTime = 0,
        time = Time.new(),
        focused = true,
        stack = { { update = function() end } },
    }, Manager)
    probe:update(0.01, 0.25)
    self:check(
        probe.frameDelta == 0.25 and probe.frameTime == 0.25 and probe.time.realDelta == 0.01,
        'Stats preserves full stall duration without changing the simulation delta'
    )
    self:scenes()
    print('PASSED ' .. self.count .. ' v106 checks')
    local path = os.getenv('KATSA_PREVIEW_PATH')
    if path then
        self.manager:draw()
        katsa.graphics.captureScreenshot(function(image)
            local file = assert(io.open(path, 'wb'))
            file:write(image:encode('png'):getString())
            file:close()
            image:release()
            print('V106 PREVIEW COMPLETE')
            katsa.event.quit()
        end)
    else
        katsa.event.quit()
    end
end

return Tests
