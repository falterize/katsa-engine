local Paths = require('./paths')

-- What the project's conf.lua (see docs/book/conf.md) says about scenes and assets:
--   startScene   = 'scenes/menu'          -- scene folder or id (none: pick from the list)
--   scenes       = 'scenes'               -- folder whose children are scenes (default: scenes/)
--   sharedAssets = { 'assets', '/abs/x' } -- extra `shared://` folders after the engine's own
--   plugins      = { ik = true }          -- plugins for every scene (a scene can set one to false)
-- A project is mounted at `_project` (conf.lua) and at the virtual root (so its `game/` modules and
-- `assets/` answer like the engine's own; the engine's files win a name clash).
local Project = {}

Project.root = '_project'

local function isScene(path)
    local FS = katsa.filesystem
    return FS.getInfo(path .. '/conf.lua', 'file') ~= nil
        and FS.getInfo(path .. '/main.lua', 'file') ~= nil
end

local function sceneId(path)
    local FS = katsa.filesystem
    if FS.getInfo(path .. '/menu-settings.lua', 'file') then
        local chunk = FS.load(path .. '/menu-settings.lua')
        local ok, menu = pcall(chunk or error)
        if ok and type(menu) == 'table' and type(menu.id) == 'string' then
            return menu.id
        end
    end
    return Paths.basename(path)
end

-- Reads the project's conf into { scenes = { {id, path} }, shared = { ... }, start }.
-- `config` is what conf.lua produced; returns nil outside a project.
function Project.read(config)
    if not config then
        return nil
    end
    local FS = katsa.filesystem
    local folder = config.scenes and Paths.normalize(config.scenes)
        or FS.getInfo('scenes', 'directory') and 'scenes'
    local scenes = {}
    if folder then
        for _, name in ipairs(FS.getDirectoryItems(folder)) do
            local path = folder .. '/' .. name
            if FS.getInfo(path, 'directory') and isScene(path) then
                scenes[#scenes + 1] = { id = sceneId(path), path = path }
            end
        end
        table.sort(scenes, function(a, b)
            return a.id < b.id
        end)
    end
    local shared = { 'assets' }
    local declared = config.sharedAssets
    for _, entry in ipairs(type(declared) == 'string' and { declared } or declared or {}) do
        local absolute = entry:match('^[/\\]') or entry:match('^%a:')
        if entry == 'assets' then
            -- the engine's own folder is always first
        elseif absolute then
            local point = '_projectShared/' .. #shared
            assert(katsa.filesystem.mount(entry, point, true))
            shared[#shared + 1] = point
        else
            shared[#shared + 1] = Paths.normalize(entry)
        end
    end
    local start = config.startScene and Paths.normalize(config.startScene)
    return { scenes = scenes, shared = shared, start = start }
end

Project.isScene = isScene

return Project
