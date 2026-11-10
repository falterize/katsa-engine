local Runtime = require('../core.runtime')
local Manager = require('../core.sceneManager')
local Display = require('../core.displayDpi')

local Bootstrap = {}

function Bootstrap.install(project, options)
    options = options or {}
    katsa.errorhandler = function(message)
        return require('source.engine.debug.errorScreen').create(
            debug.traceback(tostring(message), 2)
        )
    end
    Runtime.initialize()
    Runtime.frameRateLimit = Runtime.validateFrameRateLimit(project.frameRateLimit or 0)
    local createScene = options.createScene
        or function(owner, source)
            local Loader = require('source.engine.scenes.loader')
            return require('source.engine.scenes.host').new(
                owner,
                Loader.open(source, nil, project.sharedAssets or 'assets')
            )
        end
    Runtime.createScene = createScene
    require('source.engine.scenes.windowScene').install()
    local manager
    local testRunner
    local testing = false
    local smoke, frames = false, 0
    local windowFocused, windowVisible = true, true
    katsa.run = require('source.engine.core.frameLoop').run

    Runtime.activeScene = function()
        return manager and manager.stack[#manager.stack]
    end

    Runtime.canReuseWindowFrame = function()
        if
            smoke
            or (testRunner and not testRunner.allowWindowFrameReuse)
            or not manager
            or #manager.stack ~= 1
        then
            return false
        end
        local scene = manager.stack[1]
        return scene.canReuseWindowFrame and scene:canReuseWindowFrame() or false
    end

    function katsa.load(arguments)
        arguments = arguments or {}
        -- Scenes read launch options (e.g. --host, --connect) from here.
        katsa.launchArguments = arguments
        local source = project.startScene
        testing = options.registry and options.registry.contains(arguments) or false
        for index, argument in ipairs(arguments) do
            if argument == '--scene' or argument == '--scene-package' then
                source = assert(
                    arguments[index + 1],
                    argument .. ' requires a scene ID, directory or archive'
                )
            elseif argument == '--smoke-test' then
                smoke, frames = true, 0
            end
        end
        if options.beforeLoad then
            options.beforeLoad(arguments)
        end
        if not testing and not smoke then
            require('source.engine.debug.session').start()
        end
        katsa.graphics.setDefaultFilter('linear', 'linear')
        manager = Manager.new(options.managerOptions)
        manager.sceneFactory, manager.startScene = createScene, project.startScene
        -- Plain functions for scripts: katsa.profiler.start('name') ... katsa.profiler.stop('name').
        local profiler = manager.profiler
        katsa.profiler = {
            start = function(name)
                return profiler:start(name)
            end,
            stop = function(name)
                return profiler:stop(name)
            end,
            scope = function(name, fn, ...)
                return profiler:scope(name, fn, ...)
            end,
            isEnabled = function()
                return profiler.enabled
            end,
        }
        -- --profile records every frame of the session and saves logs/profile-*.json and .csv on quit.
        for _, argument in ipairs(arguments) do
            if argument == '--profile' then
                manager.profiler:startRecording({
                    scene = source,
                    loading = manager.profiler.loading,
                    started = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                })
            end
        end
        assert(manager:switch(createScene, source))
        if options.registry then
            testRunner = options.registry.create(arguments, manager)
        end
    end

    function katsa.filedropped(file)
        file:open('r')
        local bytes = file:read()
        file:close()
        local data = katsa.filesystem.newFileData(bytes, file:getFilename():match('[^/\\]+$'))
        manager:switch(createScene, data)
    end

    function katsa.update(dt)
        if Display.update(dt) then
            katsa.resize(katsa.graphics.getDimensions())
        end
        manager:update(math.min(dt, 0.1), Runtime.frameDelta or dt)
        local windowsStart = manager.profiler:begin()
        require('source.engine.scenes.windowScene').updateAll(dt)
        manager.profiler:finish('Window scenes', windowsStart)
        if testRunner then
            testRunner:update(dt)
        end
    end

    function katsa.draw()
        manager:draw()
        manager.profiler:frame()
        if testRunner then
            testRunner:draw()
        end
        if smoke then
            frames = frames + 1
            if frames == 10 then
                assert(#manager.journal.entries == 0, 'Scene reported runtime errors')
                print('PASSED SMOKE: ten update/render frames')
                katsa.event.quit()
            end
        end
    end

    function katsa.resize(w, h)
        Runtime.windowFrameDirty = true
        for _, scene in ipairs(manager.stack) do
            if scene.input then
                scene.input:reset()
            end
            if scene.resize then
                scene:resize(w, h)
            end
        end
    end

    -- The OS resize loop (dragging a window edge) blocks the frame loop; the platform calls this
    -- to re-fit the scenes and draw one frame at the new size.
    if katsa.platform and katsa.platform.onLiveResize then
        local lastWidth, lastHeight
        katsa.platform:onLiveResize(function(w, h)
            if w ~= lastWidth or h ~= lastHeight then
                lastWidth, lastHeight = w, h
                katsa.resize(w, h)
            end
            -- The game keeps running while the window is held: one frame of update and draw.
            katsa.update(math.min(katsa.timer.step(), 0.1))
            katsa.graphics.origin()
            katsa.graphics.clear(katsa.graphics.getBackgroundColor())
            katsa.draw()
            katsa.graphics.present()
        end)
    end

    function katsa.touchpressed(id, x, y)
        manager:dispatch('pointerpressed', id, x, y)
    end

    function katsa.touchmoved(id, x, y, dx, dy)
        manager:dispatch('pointermoved', id, x, y, dx, dy)
    end

    function katsa.touchreleased(id, x, y)
        manager:dispatch('pointerreleased', id, x, y)
    end

    function katsa.mousepressed(x, y, button, istouch)
        if not istouch then
            manager:dispatch('mousebutton', button, true)
        end
        if not istouch and button == 1 then
            manager:dispatch('pointerpressed', 'mouse', x, y)
        end
    end

    function katsa.mousemoved(x, y, dx, dy, istouch)
        if not istouch then
            manager:dispatch('pointermoved', 'mouse', x, y, dx, dy)
        end
    end

    function katsa.mousereleased(x, y, button, istouch)
        if not istouch then
            manager:dispatch('mousebutton', button, false)
        end
        if not istouch and button == 1 then
            manager:dispatch('pointerreleased', 'mouse', x, y)
        end
    end

    function katsa.wheelmoved(x, y)
        manager:dispatch('wheelmoved', x, y)
    end

    function katsa.textinput(text)
        manager:dispatch('textinput', text)
    end

    -- Controllers: the platform reports instance ids, scenes receive katsa.gamepad objects.
    function katsa.gamepadadded(id)
        manager:dispatch('gamepadadded', katsa.gamepad.get(id))
    end

    function katsa.gamepadremoved(id)
        manager:dispatch('gamepadremoved', katsa.gamepad.forget(id))
    end

    function katsa.gamepadpressed(id, button)
        manager:dispatch('gamepadpressed', katsa.gamepad.get(id), button)
    end

    function katsa.gamepadreleased(id, button)
        manager:dispatch('gamepadreleased', katsa.gamepad.get(id), button)
    end

    function katsa.gamepadaxis(id, axis, value)
        manager:dispatch('gamepadaxis', katsa.gamepad.get(id), axis, value)
    end

    function katsa.keyreleased(key)
        manager:dispatch('keyreleased', key)
    end

    function katsa.keypressed(key)
        -- F11 toggles fullscreen in every scene (desktop only; Alt+Enter does too).
        if
            key == 'f11'
            or key == 'return' and (katsa.keyboard.isDown('lalt') or katsa.keyboard.isDown('ralt'))
        then
            if katsa.window.toggleFullscreen then
                katsa.window.toggleFullscreen()
            end
            return
        end
        manager:dispatch('keypressed', key)
    end

    function katsa.focus(focused)
        Runtime.windowFrameDirty = true
        windowFocused = focused
        if manager then
            manager:focus(windowFocused and windowVisible)
        end
    end

    function katsa.visible(visible)
        Runtime.windowFrameDirty = true
        windowVisible = visible
        if manager then
            manager:focus(windowFocused and windowVisible)
        end
    end

    function katsa.quit()
        require('source.engine.scenes.windowScene').closeAll()
        if manager then
            local recording = manager.profiler:stopRecording()
            if recording and #recording.rows > 0 then
                for _, format in ipairs({ 'json', 'csv' }) do
                    local ok, path = pcall(manager.profiler.save, recording, format)
                    katsa.log.write(
                        ok and 'log' or 'warn',
                        'Profile ' .. tostring(path),
                        'profiler'
                    )
                end
            end
            manager:release()
        end
    end

    function katsa.errorhandler(message)
        local traceback = debug.traceback(tostring(message), 2)
        if manager and manager.journal then
            manager.journal:record('Runtime', traceback, nil, 'errorhandler')
        else
            katsa.log.error(traceback, 'errorhandler')
        end
        print(traceback)
        if testing or smoke then
            katsa.filesystem.write('testError.txt', traceback)
            return function()
                return 1
            end
        end
        return require('source.engine.debug.errorScreen').create(traceback)
    end
end

return Bootstrap
