-- Program start for every way of running katsa: the standalone `katsa` host, a game fused into an
-- executable, and the development launcher. It mirrors katsa's boot: choose the game source, read
-- conf.lua, create the window, run main.lua and drive the frame loop.
--
-- host: { exe = path to the executable, args = { ... }, archive = Archive | nil (appended to exe) }
local Boot = {}

-- Exit status of a run stopped with Ctrl+C (128 + SIGINT).
local INTERRUPTED = 130

-- LuaJIT turns SIGINT into the Lua error "interrupted!". That is a request to stop, not a crash,
-- so it must not reach the error screen or print a traceback.
function Boot.isInterrupt(message)
    return type(message) == 'string' and message:find('interrupted!', 1, true) ~= nil
end

local function exeDirectory(exe)
    return exe and exe:match('^(.*)[/\\][^/\\]*$') or '.'
end

local function installSearcher(FS)
    local function searcher(name)
        local path = name:gsub('%.', '/')
        local file = path .. '.lua'
        if FS.getInfo(file, 'file') then
            local chunk, message = FS.load(file)
            return chunk or error(message, 0)
        end
        file = path .. '/init.lua'
        if FS.getInfo(file, 'file') then
            local chunk, message = FS.load(file)
            return chunk or error(message, 0)
        end
        return "\n\tno file '" .. path .. ".lua' in the game source"
    end
    table.insert(package.loaders or package.searchers, 2, searcher)
    _G.require = require('source.katsa.core.relativeRequire').wrap(require)
end

-- Game source choice: first non-option argument, else the fused archive, else the working
-- directory.
-- Returns the source and its kind: 'game' (own main.lua), 'project' or 'scene' (both run on the engine).
local function chooseSource(host, FS, nativeLib)
    local args = host.args or {}
    local positional
    for _, value in ipairs(args) do
        if value == '--' then
            break -- everything after a lone `--` is a game argument, never the game path
        elseif not value:find('^%-%-') then
            positional = value
            break
        end
    end
    if positional then
        local kind = nativeLib.stat(positional)
        if not kind then
            return nil, 'Cannot find game source: ' .. positional
        end
        FS.setSource(positional, false)
        -- conf.lua without main.lua is a project (settings and scenes); conf.lua with main.lua but
        -- without its own engine copy is a scene. Both run on the engine in the working directory.
        local project = FS.getInfo('conf.lua', 'file') and not FS.getInfo('main.lua', 'file')
        local scene = FS.getInfo('conf.lua', 'file')
            and FS.getInfo('main.lua', 'file')
            and not FS.getInfo('source/engine', 'directory')
        if project or scene then
            if nativeLib.stat('main.lua') ~= 'file' then
                return nil, 'A project or scene needs the engine to run it: start katsa from the engine folder.'
            end
            FS.setSource('.', false)
            local mounts = project and { '_project', '' } or { '_scene' }
            for _, point in ipairs(mounts) do
                local ok, message = FS.mount(positional, point, true)
                if not ok then
                    return nil, message
                end
            end
            return positional, project and 'project' or 'scene'
        end
        return positional, 'game'
    end
    if host.archive and host.archive:has('main.lua') then
        FS.setSource(host.archive, true)
        return host.exe, 'game'
    end
    if nativeLib.stat('main.lua') == 'file' then
        FS.setSource('.', false)
        return '.', 'game'
    end
    return nil, 'No game to run.\nUsage: katsa <game folder | game.katsa | game.zip>'
end

-- What a scene run on its own may take from its conf.lua for the application itself.
local SCENE_APPLICATION_KEYS = { 'identity', 'title', 'window', 'audio', 'modules', 'console', 'externalStorage' }

local function defaultConfig()
    return {
        identity = nil,
        version = '0.2.0',
        console = false,
        audio = { mic = false, mixwithsystem = true },
        window = {
            title = 'Untitled',
            width = 800,
            height = 600,
            borderless = false,
            resizable = false,
            minwidth = 1,
            minheight = 1,
            fullscreen = false,
            fullscreentype = 'desktop',
            vsync = 1,
            msaa = 0,
            depth = nil,
            stencil = nil,
            display = 1,
            highdpi = false,
            usedpiscale = true,
            x = nil,
            y = nil,
        },
        modules = {},
    }
end

local function report(message)
    io.stderr:write(tostring(message), '\n')
end

-- Returns the process exit status.
local function run(host)
    -- LuaJIT's default collector lets a game with a small live heap balloon to hundreds of MB of
    -- garbage and then pause for tens of milliseconds. Start cycles earlier and sweep faster so
    -- the heap stays near its live size and each step is short.
    collectgarbage('setpause', 120)
    collectgarbage('setstepmul', 400)
    local Native = require('source.katsa.core.native')
    local exeDir = exeDirectory(host.exe)
    Native.addDirectory(exeDir)
    Native.addDirectory(exeDir .. '/lib')
    local nativeLib = require('source.katsa.core.nativeLib')
    local katsa = require('source.katsa')
    _G.katsa = katsa
    local FS = katsa.filesystem
    if not package.loaded.utf8 and not package.preload.utf8 then
        package.preload.utf8 = function()
            return require('source.katsa.core.utf8')
        end
    end

    local source, kind = chooseSource(host, FS, nativeLib)
    if not source then
        report(kind)
        return 1
    end
    local argv = { [0] = host.exe }
    for i, value in ipairs(host.args or {}) do
        argv[i] = value
    end
    if kind == 'scene' then
        -- The scene path stays the "game path" (so a server child process starts the same way)
        -- and the engine receives it as `--scene`.
        local at
        for i, value in ipairs(argv) do
            if value == source then
                at = i
                break
            end
        end
        table.insert(argv, at + 1, '--scene')
        table.insert(argv, at + 2, source)
    end
    _G.arg = argv
    installSearcher(FS)
    -- What it takes to start this game again (a server child process): the executable, the dev
    -- launcher script and the game path when one was given.
    local launch = { host.exe }
    for _, value in ipairs(host.prefix or {}) do
        launch[#launch + 1] = value
    end
    local explicit = false
    for _, value in ipairs(host.args or {}) do
        if value == '--' then
            break
        elseif not value:find('^%-%-') then
            launch[#launch + 1] = source
            explicit = true
            break
        end
    end
    katsa.process.setLaunchBase(launch, explicit)

    local config = defaultConfig()
    -- conf.lua returns the project table. A project or scene runs over the engine's own conf.lua
    -- (defaults) with its own conf.lua applied on top.
    local Conf = require('source.katsa.core.conf')
    local conf = {}
    local ok, err = pcall(function()
        if kind == 'game' then
            conf = FS.getInfo('conf.lua', 'file') and Conf.read(FS, 'conf.lua') or {}
            return
        end
        conf = Conf.read(FS, 'conf.lua')
        local own = (kind == 'project' and '_project' or '_scene') .. '/conf.lua'
        if FS.getInfo(own, 'file') then
            local values = Conf.read(FS, own)
            if kind == 'scene' then
                -- A scene started on its own may name its window and save folder; the rest of its
                -- conf is the scene's own business.
                local applied = {}
                for _, key in ipairs(SCENE_APPLICATION_KEYS) do
                    applied[key] = values[key]
                end
                values = applied
            end
            Conf.merge(conf, values)
        end
    end)
    if not ok then
        report('Error in conf.lua: ' .. tostring(err))
        return 1
    end
    if next(conf) then
        require('source.engine.core.windowConfig').apply(config, conf)
    end
    katsa.projectConfig = conf
    local base = source:match('([^/\\]+)%.[%w]+$') or source:match('([^/\\]+)$') or 'game'
    FS.setIdentity(config.identity or base)

    local Platform = require('source.katsa.platform.sdl2')
    -- --server runs without a display (see Runtime.headless).
    local headless = false
    for _, value in ipairs(host.args or {}) do
        headless = headless or value == '--server'
    end
    local platform, message = Platform.new({
        title = config.window and config.window.title,
        headless = headless,
    })
    if not platform then
        report('Cannot start the platform layer: ' .. tostring(message))
        return 1
    end
    katsa.attachPlatform(platform)
    local prefPath = platform:getPrefPath('Katsa', FS.getIdentity())
    if prefPath then
        FS.setSaveDirectory(prefPath)
    end

    local window = config.window
    if window then
        local ok, reason = katsa.window.setMode(window.width, window.height, {
            title = window.title,
            resizable = window.resizable,
            borderless = window.borderless,
            fullscreen = window.fullscreen,
            fullscreentype = window.fullscreentype,
            vsync = window.vsync,
            msaa = window.msaa,
            depth = window.depth,
            stencil = window.stencil,
            minwidth = window.minwidth,
            minheight = window.minheight,
            highdpi = window.highdpi,
            x = window.x,
            y = window.y,
        })
        if not ok then
            report('Cannot create the window: ' .. tostring(reason))
            platform:close()
            return 1
        end
    end

    local ok, err = xpcall(function()
        require('main')
    end, debug.traceback)
    local loop
    if ok then
        ok, err = xpcall(katsa.run, debug.traceback)
        loop = err
    end
    local status = 0
    if not ok and Boot.isInterrupt(err) then
        platform:close()
        return INTERRUPTED
    end
    if not ok then
        loop = katsa.errorhandler(err)
    end
    while true do
        local good, result = xpcall(loop, debug.traceback)
        if not good and Boot.isInterrupt(result) then
            status = INTERRUPTED
            break
        elseif not good then
            loop = katsa.errorhandler(result)
        elseif result ~= nil then
            status = tonumber(result) or 0
            break
        end
    end
    platform:close()
    return status
end

-- A server runs in a console window of its own that closes with the process, which hides why it
-- stopped: after a failure it waits for Enter so the message can be read.
function Boot.start(host)
    local status = run(host)
    if status ~= 0 and status ~= INTERRUPTED then
        for _, value in ipairs(host.args or {}) do
            if value == '--server' then
                io.stderr:write('\nThe server stopped (status ', tostring(status), '). Press Enter to close.\n')
                io.stderr:flush()
                io.read()
                break
            end
        end
    end
    return status
end

return Boot
