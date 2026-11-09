-- katsa: the engine's own runtime API (graphics, audio, physics, filesystem, ...).
-- Modules load lazily; heavy ones (graphics, audio, physics) are only required when first touched.
local katsa = {
    _VERSION = '0.2.0',
    _NAME = 'Katsa',
}

local lazy = {
    timer = 'source.katsa.core.timer',
    log = 'source.katsa.core.log',
    math = 'source.katsa.core.math',
    data = 'source.katsa.core.data',
    filesystem = 'source.katsa.core.filesystem',
    event = 'source.katsa.core.event',
    system = 'source.katsa.core.system',
    window = 'source.katsa.core.window',
    keyboard = 'source.katsa.core.keyboard',
    mouse = 'source.katsa.core.mouse',
    gamepad = 'source.katsa.core.gamepad',
    graphics = 'source.katsa.graphics',
    image = 'source.katsa.image',
    sound = 'source.katsa.sound',
    audio = 'source.katsa.audio',
    physics = 'source.katsa.physics',
    net = 'source.katsa.net',
    thread = 'source.katsa.thread',
}

setmetatable(katsa, {
    __index = function(self, key)
        local path = lazy[key]
        if path then
            local ok, module = pcall(require, path)
            if ok then
                rawset(self, key, module)
                return module
            end
            if not tostring(module):find("module '" .. path .. "' not found", 1, true) then
                error(module, 0)
            end
        end
        return nil
    end,
})

-- Runtime version: major, minor, revision, codename.
function katsa.getVersion()
    return 1, 0, 0, 'Katsa'
end

katsa.arg = {}
-- Game arguments follow the game path: `katsa <game> --flag` passes `--flag`.
-- Options before the game path belong to the runtime. Arguments after a lone `--` are always
-- game arguments.
function katsa.arg.parseGameArguments(argv)
    argv = argv or {}
    local result, seenGame = {}, false
    for i = 1, #argv do
        local value = argv[i]
        if seenGame then
            result[#result + 1] = value
        elseif value == '--' then
            seenGame = true
        elseif value:sub(1, 2) ~= '--' then
            seenGame = true
        end
    end
    return result
end

-- Event name -> handler. Each forwards to the game callback of the same name when it exists.
katsa.handlers = setmetatable({}, {
    __index = function(self, name)
        local handler = function(...)
            local callback = katsa[name]
            if callback then
                return callback(...)
            end
        end
        rawset(self, name, handler)
        return handler
    end,
})
katsa.handlers.keypressed = function(key, scancode, isrepeat)
    if isrepeat and not katsa.keyboard.acceptsRepeat() then
        return
    end
    if katsa.keypressed then
        return katsa.keypressed(key, scancode, isrepeat)
    end
end

-- Default frame loop (games may replace katsa.run, as the engine does).
function katsa.run()
    if katsa.load then
        katsa.load(katsa.arg.parseGameArguments(arg), arg)
    end
    katsa.timer.step()
    local dt = 0
    return function()
        katsa.event.pump()
        for name, a, b, c, d, e, f in katsa.event.poll() do
            if name == 'quit' and (not katsa.quit or not katsa.quit()) then
                return a or 0
            end
            katsa.handlers[name](a, b, c, d, e, f)
        end
        dt = katsa.timer.step()
        if katsa.update then
            katsa.update(dt)
        end
        local graphics = katsa.graphics
        if graphics and graphics.isActive() then
            graphics.origin()
            graphics.clear(graphics.getBackgroundColor())
            if katsa.draw then
                katsa.draw()
            end
            graphics.present()
        end
        katsa.timer.sleep(0.001)
    end
end

-- Last-resort error handler: reports to stderr and exits with status 1. The engine installs a
-- richer one.
function katsa.errorhandler(message)
    io.stderr:write(tostring(message), '\n', debug.traceback(), '\n')
    return function()
        return 1
    end
end

-- Wires the core modules to a platform backend.
function katsa.attachPlatform(platform)
    katsa.platform = platform
    katsa.window.setPlatform(platform)
    katsa.keyboard.setPlatform(platform)
    katsa.mouse.setPlatform(platform)
    katsa.gamepad.setPlatform(platform)
    katsa.system.setPlatform(platform)
    katsa.event.setSource(function()
        return platform:poll()
    end)
end

return katsa
