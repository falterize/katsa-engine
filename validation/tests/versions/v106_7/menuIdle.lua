local Application = require('source.game.runtime.application')
local Runtime = require('source.engine.core.runtime')
local FrameLoop = require('source.engine.core.frameLoop')

local Tests = {}

local function loop(tester)
    local original = katsa
    local frameDelta = Runtime.frameDelta
    local previousPolicy, previousDirty, previousTimings =
        Runtime.canReuseWindowFrame, Runtime.windowFrameDirty, Runtime.timings
    local draws, presents, clears, elapsed, slept = 0, 0, 0, 0, 0
    local reused = false
    local ok, message = pcall(function()
        katsa = {
            timer = {
                getTime = function()
                    return elapsed
                end,
                step = function()
                    return 1 / 120
                end,
                sleep = function(duration)
                    slept = slept + duration
                    elapsed = elapsed + duration
                end,
            },
            event = {
                pump = function() end,
                poll = function()
                    return function() end
                end,
            },
            graphics = {
                isActive = function()
                    return true
                end,
                origin = function() end,
                getBackgroundColor = function()
                    return 0, 0, 0, 1
                end,
                clear = function()
                    clears = clears + 1
                end,
                present = function()
                    presents = presents + 1
                end,
            },
            window = {
                hasFocus = function()
                    return true
                end,
            },
            update = function()
                elapsed = elapsed + 0.0001
            end,
            draw = function()
                draws = draws + 1
            end,
        }
        Runtime.canReuseWindowFrame = function()
            return reused
        end
        Runtime.windowFrameDirty = false
        local tick = FrameLoop.run()
        tick()
        tester:check(
            draws == 1 and presents == 1 and slept == 0,
            'Active rendering retains the uncapped foreground path'
        )
        reused = true
        for _ = 1, 600 do
            tick()
        end
        tester:check(
            draws == 1 and presents == 1 and clears == 1,
            'Idle interface frames do not clear, redraw or present an unchanged image'
        )
        tester:check(
            slept > 4.8 and Runtime.timings.frameReused,
            'Idle polling yields CPU time instead of spinning without useful work'
        )
        Runtime.windowFrameDirty = true
        tick()
        tester:check(
            draws == 2 and presents == 2 and not Runtime.windowFrameDirty,
            'Focus/resize damage forces a fresh presentation'
        )
        reused, slept = false, 0
        tick()
        tick()
        tester:check(
            draws == 4 and presents == 4 and slept == 0,
            'Leaving an idle interface restores uncapped scene rendering immediately'
        )
    end)
    katsa = original
    Runtime.frameDelta = frameDelta
    Runtime.canReuseWindowFrame, Runtime.windowFrameDirty, Runtime.timings =
        previousPolicy, previousDirty, previousTimings
    assert(ok, message)
end

function Tests.run(tester)
    loop(tester)
    local menu = assert(tester.manager:switch(Application.new, 'menu'))
    tester:check(not menu:canReuseWindowFrame(), 'A newly opened Menu paints its first frame')
    menu:draw()
    tester:check(menu:canReuseWindowFrame(), 'An unchanged Menu opts into window-frame reuse')
    local owned = #menu.resources.owned
    for _ = 1, 600 do
        tester.manager:update(1 / 120)
        assert(menu:canReuseWindowFrame(), 'Idle Menu became dirty without a visual change')
    end
    tester:check(
        #menu.resources.owned == owned,
        'Several seconds of idle Menu polling retain a bounded resource set'
    )
    menu.tagButton.text = 'Changed tag label'
    tester:check(not menu:canReuseWindowFrame(), 'Direct text edits invalidate the presented Menu')
    menu:draw()
    menu.tagChooser.visible = true
    tester:check(not menu:canReuseWindowFrame(), 'Opening the tag chooser requests a repaint')
    menu:draw()
    menu.tagChooser.visible = false
    menu.setTags({ physics = true })
    local shown = #menu.ui:find('LevelList', true).children
    tester:check(
        not menu:canReuseWindowFrame(),
        'Tag changes rebuild and repaint the scene list'
    )
    menu:draw()
    tester:check(shown > 0 and shown < 20, 'Selecting the physics tag narrows the scene list (' .. shown .. ')')
    menu.setTags({})
    menu:draw()
    local list = menu.ui:find('LevelList', true)
    menu.ui:scrollBy(list, 48)
    tester:check(not menu:canReuseWindowFrame(), 'Scrolling invalidates the retained Menu image')
    menu:draw()
    -- The layout observer determines animation from nodes, not a caller-owned flag.
    local effect = menu.ui:create('Shader2D', {
        name = 'IdleAnimationProbe',
        size = { 1, 0, 1, 0 },
        shaderPath = 'assets/shaders/examples/uiPulse.glsl',
    }, menu.ui.content)
    menu.ui:layout()
    menu.state._paintRevision = menu.ui.revision
    tester:check(not menu:canReuseWindowFrame(), 'Animated menu shaders never reuse a frozen frame')
    effect:destroy()
    menu:resize(katsa.graphics.getDimensions())
    tester:check(
        not menu:canReuseWindowFrame(),
        'Resizing invalidates the previous Menu presentation'
    )
    local game = assert(tester.manager:switch(require('source.game.runtime.game').new, 'original'))
    tester:check(not game.canReuseWindowFrame, 'Gameplay does not opt into Menu idle pacing')
    menu = assert(tester.manager:switch(Application.new, 'menu'))
    tester:check(
        not menu:canReuseWindowFrame(),
        'Returning from gameplay starts with a fresh Menu image'
    )
end

function Tests.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED menu idle ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable({ manager = manager, count = 0 }, { __index = Tests })
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS menu idle', label)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    Tests.run(self)
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' menu idle checks')
    katsa.event.quit()
end

return Tests
