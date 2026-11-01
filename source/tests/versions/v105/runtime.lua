local Physics = require('source.engine.physics')
local World = require('source.engine.world.world')
local UI = require('source.engine.ui')
local Jobs = require('source.engine.physics.3d.backends.jolt.native.jobs')

local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    return setmetatable({ manager = manager, count = 0 }, Tests)
end

function Tests:update() end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v105', label)
end

function Tests:scrolling()
    local resources = self.manager.resources:scope()
    local ui = UI.new(800, 600, resources)
    local frame = ui:scroll({
        position = { 0, 20, 0, 20 },
        size = { 0, 200, 0, 120 },
        scrollingDirection = 'XY',
        canvasSize = { 0, 500, 0, 400 },
    }, ui.content)
    local child =
        ui:create('Frame', { position = { 0, 80, 0, 70 }, size = { 0, 40, 0, 30 } }, frame)
    ui:layout()
    self:check(
        frame.absoluteCanvasSize[1] == 500 and frame.absoluteCanvasSize[2] == 400,
        'Manual canvas resolves both dimensions'
    )
    ui:scrollBy(frame, 35, 50)
    ui:layout()
    self:check(child._x == 50 and child._y == 55, 'Both scroll axes translate child layout')
    self:check(
        frame.canvasPosition[1] == 50 and frame.canvasPosition[2] == 35,
        'CanvasPosition follows input'
    )
    frame.ScrollingDirection = 'X'
    ui:layout()
    self:check(
        frame.scrollY == 0 and frame.scrollX == 50 and not frame._verticalBar,
        'Changing direction clamps the disabled axis and hides its scrollbar'
    )
    frame.canvasPosition = { 999, 999 }
    ui:layout()
    self:check(
        frame.scrollX == 300 and frame.scrollY == 0,
        'Programmatic positions clamp to bounds'
    )
    frame.scrollX = 10
    ui:layout()
    self:check(frame.canvasPosition[1] == 10, 'Legacy scalar position edits remain live')
    frame.scrollingEnabled = false
    ui:scrollBy(frame, 100, 100)
    ui:layout()
    self:check(
        frame.scrollX == 10 and not frame._horizontalBar,
        'ScrollingEnabled blocks user input'
    )
    frame.scrollingEnabled, frame.scrollingDirection = true, 'XY'
    frame.canvasSize, frame.automaticCanvasSize = { 0, 0, 0, 0 }, 'XY'
    frame.canvasPosition = { 0, 0 }
    ui:layout()
    self:check(
        frame.absoluteCanvasSize[1] == 120 and frame.absoluteCanvasSize[2] == 100,
        'AutomaticCanvasSize measures both axes'
    )
    child.position = { 0, 400, 0, 300 }
    ui:layout()
    self:check(
        frame.absoluteCanvasSize[1] == 440 and frame.absoluteCanvasSize[2] == 330,
        'Automatic extents refresh after child movement'
    )
    local calculations = frame._lengthCalculations
    ui:layout()
    ui:layout()
    self:check(
        frame._lengthCalculations == calculations,
        'Unchanged automatic canvas reuses its layout'
    )
    child.visible = false
    ui:layout()
    self:check(
        frame.absoluteCanvasSize[1] == 0 and frame.absoluteCanvasSize[2] == 0,
        'Hidden content stops contributing to automatic canvas'
    )
    child.visible = true
    frame.canvasSize, frame.automaticCanvasSize = { 0, 500, 0, 400 }, 'None'
    frame.horizontalScrollBarInset, frame.verticalScrollBarInset = 'ScrollBar', 'ScrollBar'
    frame.scrollBarThickness, frame.verticalScrollBarPosition = 10, 'Left'
    ui:layout()
    self:check(
        frame.absoluteWindowSize[1] == 190 and frame.absoluteWindowSize[2] == 110,
        'Scrollbar insets reserve both viewport dimensions'
    )
    self:check(child._x == 430, 'Left scrollbar inset offsets the content origin')
    frame.canvasSize = { 1, 0, 1, 0 }
    frame.horizontalScrollBarInset, frame.verticalScrollBarInset = 'None', 'None'
    ui:layout()
    self:check(
        frame.absoluteCanvasSize[1] == 200 and frame.absoluteCanvasSize[2] == 120,
        'Canvas scale components resolve relative to frame size'
    )
    frame.canvasSize = { 0, 500, 0, 400 }
    frame.canvasPosition = { 0, 0 }
    ui:layout()
    frame:pointer(ui, 'press', 40, 40, 'drag')
    frame:pointer(ui, 'move', 20, 10, 'drag')
    frame:pointer(ui, 'release', 20, 10, 'drag')
    ui:layout()
    self:check(frame.scrollX == 20 and frame.scrollY == 30, 'Pointer drag supports both axes')
    frame.scrollingDirection, frame.canvasPosition = 'X', { 0, 0 }
    ui:layout()
    ui:wheel(30, 30, -1, 0)
    ui:layout()
    self:check(frame.scrollX == 48 and frame.scrollY == 0, 'Vertical wheel maps to X-only frames')
    frame.scrollingDirection, frame.canvasPosition = 'XY', { 0, 0 }
    ui:layout()
    ui:wheel(30, 30, 0, -1)
    ui:layout()
    self:check(frame.scrollX == 48, 'Horizontal wheel reaches horizontal canvas position')
    local schema = require('source.engine.editor.inspectors.schema')
    self:check(
        #schema.options(frame, 'scrollingDirection') == 3,
        'Inspector exposes X, Y and XY options'
    )
    self:check(
        schema.reason(frame, 'absoluteCanvasSize') ~= nil,
        'Inspector treats resolved canvas dimensions as read-only'
    )
    frame.scrollingDirection = 'Invalid'
    self:check(not pcall(ui.layout, ui), 'Invalid direction fails with a clear validation error')
    frame.scrollingDirection = 'XY'
    self:check(not pcall(function()
        frame.canvasPosition = { 0 / 0, 0 }
    end), 'Nonfinite canvas position is rejected')
    frame.canvasPosition = { 0, 0 }
    ui:layout()
    ui:drawRaw()
    ui:release()
    resources:release()
end

function Tests:parallel()
    self:check(Jobs.C ~= nil, 'Native contact bridge is loaded')
    for _, workers in ipairs({ 0, 2, 4 }) do
        local resources = self.manager.resources:scope()
        local world = World.new(resources)
        world.physics = Physics.new({ backend = 'jolt', workerThreads = workers })
        local physics = world.physics
        world:create('Body3D', {
            name = 'Floor',
            bodyType = 'Static',
            position = { 0, -10, 0 },
            size = { 1000, 20, 1000 },
        })
        local bodies = {}
        for index = 1, 144 do
            bodies[index] = world:create('Body3D', {
                name = 'Box' .. index,
                position = {
                    (index % 12) * 24 - 144,
                    10 + math.floor((index - 1) / 12) * 19,
                    0,
                },
                size = { 20, 20, 20 },
                autoSleep = false,
            })
        end
        for _ = 1, 90 do
            world:updateNodes(1 / 60)
            physics:update(1 / 60)
        end
        self:check(
            physics.adapter.workerThreads == workers,
            'Worker count is explicit: ' .. workers
        )
        self:check(
            next(physics.adapter.contacts) ~= nil,
            'Contacts survive native event transfer: ' .. workers
        )
        if workers > 0 then
            self:check(
                physics.stats.workerContactCallbacks > 0,
                'Contact callbacks run on worker threads: ' .. workers
            )
        else
            self:check(
                physics.stats.workerContactCallbacks == 0,
                'Synchronous mode stays on the calling thread'
            )
        end
        for _, node in ipairs(bodies) do
            assert(
                node.position[2] == node.position[2] and node.position[2] > -100,
                'Parallel body state must remain finite and above the floor'
            )
        end
        self:check(true, 'All body transforms remain bounded: ' .. workers)
        for index = 1, 72 do
            bodies[index]:destroy()
        end
        for index = 1, 72 do
            world:create('Body3D', { position = { index * 2, 300, 0 }, size = { 10, 10, 10 } })
        end
        physics:update(1 / 60)
        self:check(true, 'Native body metadata survives removal and ID reuse: ' .. workers)
        world:release()
        resources:release()
    end
    local count = require('source.engine.physics.3d.backends.jolt.driver').liveWorldCount()
    self:check(
        not pcall(Physics.new, { backend = 'jolt', workerThreads = -1 }),
        'Invalid thread counts are rejected'
    )
    self:check(
        require('source.engine.physics.3d.backends.jolt.driver').liveWorldCount() == count,
        'Rejected settings do not leak a native world'
    )
end

function Tests:settings()
    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    world.physics = Physics.new({ backend = 'jolt', workerThreads = 0 })
    local node = world:create('Body3D', { autoSleep = false })
    node:update(0)
    self:check(node.body.settings.autoSleep == false, 'Body3D forwards explicit sleep policy')
    node.friction = -1
    self:check(not pcall(node.update, node, 0), 'Invalid changed settings fail validation')
    self:check(not pcall(node.update, node, 0), 'Failed settings remain pending for retry')
    node.friction, node.autoSleep = 0.8, true
    node:update(0)
    self:check(
        node.body.settings.friction == 0.8 and node.body.settings.autoSleep == true,
        'Corrected settings commit and refresh the snapshot'
    )
    local changes = node._settingsDelta
    node:update(0)
    self:check(
        node._settingsDelta == changes and not node._settingsPending,
        'Unchanged node settings keep the cached inputs'
    )
    world:release()
    resources:release()
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:scrolling()
    self:parallel()
    self:settings()
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' v105 checks')
    katsa.event.quit()
end

return Tests
