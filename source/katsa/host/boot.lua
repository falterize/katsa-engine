-- Program start for every way of running katsa: the standalone `katsa` host, a game fused into an
-- executable, and the development launcher. It mirrors LÖVE's boot: choose the game source, read
-- conf.lua, create the window, run main.lua and drive the frame loop.
--
-- host: { exe = path to the executable, args = { ... }, archive = Archive | nil (appended to exe) }
local Boot = {}

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
end

-- Game source choice: first non-option argument, else the fused archive, else the working directory.
local function chooseSource(host, FS, nativeLib)
    local args = host.args or {}
    local positional
    for _, value in ipairs(args) do
        if value ~= '--' and not value:find('^%-%-') then
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
        return positional
    end
    if host.archive and host.archive:has('main.lua') then
        FS.setSource(host.archive, true)
        return host.exe
    end
    if nativeLib.stat('main.lua') == 'file' then
        FS.setSource('.', false)
        return '.'
    end
    return nil, 'No game to run.\nUsage: katsa <game folder | game.katsa | game.love | game.zip>'
end

local function defaultConfig()
    return {
        identity = nil,
        version = '0.2.0',
        console = false,
        gammacorrect = false,
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
function Boot.start(host)
    local Native = require('source.katsa.core.native')
    local exeDir = exeDirectory(host.exe)
    Native.addDirectory(exeDir)
    Native.addDirectory(exeDir .. '/lib')
    local nativeLib = require('source.katsa.core.nativeLib')
    local katsa = require('source.katsa')
    _G.katsa = katsa
    local FS = katsa.filesystem

    local argv = { [0] = host.exe }
    for i, value in ipairs(host.args or {}) do
        argv[i] = value
    end
    _G.arg = argv

    local source, problem = chooseSource(host, FS, nativeLib)
    if not source then
        report(problem)
        return 1
    end
    installSearcher(FS)

    local config = defaultConfig()
    if FS.getInfo('conf.lua', 'file') then
        local ok, err = pcall(function()
            local chunk = assert(FS.load('conf.lua'))
            chunk()
            if katsa.conf then
                katsa.conf(config)
            end
        end)
        if not ok then
            report('Error in conf.lua: ' .. tostring(err))
            return 1
        end
    end
    FS.setIdentity(config.identity or (source:match('([^/\\]+)%.[%w]+$') or source:match('([^/\\]+)$') or 'game'))

    local Platform = require('source.katsa.platform.sdl2')
    local platform, message = Platform.new({ title = config.window and config.window.title })
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
    if not ok then
        loop = katsa.errorhandler(err)
    end
    while true do
        local good, result = xpcall(loop, debug.traceback)
        if not good then
            loop = katsa.errorhandler(result)
        elseif result ~= nil then
            status = tonumber(result) or 0
            break
        end
    end
    platform:close()
    return status
end

return Boot
