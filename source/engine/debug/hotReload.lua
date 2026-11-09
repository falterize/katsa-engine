-- Hot reload (development only): watches the source and asset folders and applies edits to the
-- running game, so a changed file shows up without restarting the program.
--
-- Start the dev host with `--hot-reload` (or KATSA_HOTRELOAD=1). What a change does:
--
--   locales/*.lua           the language is read again, Labels update in place
--   tilesets/*.lua          every TileMap loads its tileset again (cells are kept)
--   *.png *.jpg textures    the pixels are replaced in the loaded textures (same size);
--                           a texture of another size restarts the scene
--   scene scripts, XML, shaders (*.glsl), other scene assets
--                           the current scene is created again from disk (scene modules are
--                           loaded per scene, so the new code runs; the window stays open)
--   source/engine, source/katsa, source/plugins
--                           reported in the log only: engine classes cannot be swapped under
--                           live objects, restart the program
--
-- The watcher polls modification times a few hundred files per tick (every `interval` seconds),
-- waits `settle` seconds after the last change so an editor can finish writing, and applies all
-- changes of a burst together. Files inside an archive never change, so a packaged game does
-- nothing here.
local HotReload = {}
HotReload.__index = HotReload

local WATCHED = { lua = true, glsl = true, png = true, jpg = true, jpeg = true, xml = true }
local ENGINE = { 'source/engine/', 'source/katsa/', 'source/plugins/' }

local function extension(path)
    return path:match('%.(%w+)$')
end

-- options: roots (folders to watch), interval (0.5), settle (0.3), budget (files per tick, 400),
-- restart = function(manager, scene) called to create the current scene again, log = function(text).
function HotReload.new(manager, options)
    options = options or {}
    local self = setmetatable({
        manager = manager,
        roots = options.roots or { 'source/game', 'source/engine', 'source/katsa', 'source/plugins', 'assets' },
        interval = options.interval or 0.5,
        settle = options.settle or 0.3,
        budget = options.budget or 400,
        restart = options.restart,
        log = options.log or function(text)
            katsa.log.write('log', '[hot reload] ' .. text)
        end,
        files = {},
        list = {},
        cursor = 1,
        clock = 0,
        lastScan = 0,
        pending = {},
        changedAt = nil,
        watched = {},
        counts = { locale = 0, tileset = 0, image = 0, restart = 0, ignored = 0 },
    }, HotReload)
    for _, root in ipairs(self.roots) do
        self:watch(root)
    end
    return self
end

-- Modification time and size: an edit within the same clock second still changes the size.
local function signature(info)
    return (info.modtime or 0) .. ':' .. (info.size or 0)
end

local function walk(path, visit)
    for _, name in ipairs(katsa.filesystem.getDirectoryItems(path)) do
        local child = path .. '/' .. name
        local info = katsa.filesystem.getInfo(child)
        if info and info.type == 'directory' then
            if name ~= '.git' and name ~= 'node_modules' then
                walk(child, visit)
            end
        elseif info and info.type == 'file' and WATCHED[extension(name) or ''] then
            visit(child, info.modtime, info.size)
        end
    end
end

-- Adds a folder to the watch list (what is there now counts as unchanged).
function HotReload:watch(root)
    if self.watched[root] then
        return
    end
    self.watched[root] = true
    walk(root, function(path, modified, size)
        if self.files[path] == nil then
            self.files[path] = signature({ modtime = modified, size = size })
            self.list[#self.list + 1] = path
        end
    end)
end

-- Finds files created after the start; a new file counts as changed.
function HotReload:rescan()
    for root in pairs(self.watched) do
        walk(root, function(path, modified, size)
            if self.files[path] == nil then
                self.files[path] = signature({ modtime = modified, size = size })
                self.list[#self.list + 1] = path
                self:_changed(path)
            end
        end)
    end
end

function HotReload:_changed(path)
    self.pending[path] = true
    self.changedAt = self.clock
end

function HotReload:_poll()
    local count = #self.list
    for _ = 1, math.min(self.budget, count) do
        if self.cursor > count then
            self.cursor = 1
        end
        local path = self.list[self.cursor]
        self.cursor = self.cursor + 1
        local info = katsa.filesystem.getInfo(path)
        if not info then
            self.files[path] = nil
            self.list[self.cursor - 1] = ''
        elseif signature(info) ~= self.files[path] then
            self.files[path] = signature(info)
            self:_changed(path)
        end
    end
end

-- What a changed path needs: 'locale', 'tileset', 'image', 'engine' or 'restart'.
function HotReload.classify(path)
    local kind = extension(path)
    for _, prefix in ipairs(ENGINE) do
        if path:sub(1, #prefix) == prefix then
            return 'engine'
        end
    end
    if kind == 'lua' and path:find('/locales/[^/]+%.lua$') then
        return 'locale'
    elseif kind == 'lua' and path:find('/tilesets/[^/]+%.lua$') then
        return 'tileset'
    elseif kind == 'png' or kind == 'jpg' or kind == 'jpeg' then
        return 'image'
    end
    return 'restart'
end

function HotReload:_apply()
    local pending = self.pending
    self.pending, self.changedAt = {}, nil
    local needsRestart, reasons = false, {}
    local resources = self.manager.resources
    for path in pairs(pending) do
        local kind = HotReload.classify(path)
        if kind == 'locale' then
            if require('source.engine.localization').get():reloadPath(path) then
                self.counts.locale = self.counts.locale + 1
                self.log('locale ' .. path)
            else
                self.counts.ignored = self.counts.ignored + 1
            end
        elseif kind == 'tileset' then
            require('source.engine.tilemap.tileSet').invalidate()
            self.counts.tileset = self.counts.tileset + 1
            self.log('tileset ' .. path)
        elseif kind == 'image' then
            local ok, replaced = pcall(resources.reloadImage, resources, path)
            if ok and replaced == 0 then
                self.counts.ignored = self.counts.ignored + 1
            elseif ok and replaced then
                self.counts.image = self.counts.image + 1
                self.log(('texture %s (%d loaded copies)'):format(path, replaced))
            else
                needsRestart, reasons[#reasons + 1] = true, path
            end
        elseif kind == 'engine' then
            self.log('engine file changed, restart the program to use it: ' .. path)
        else
            needsRestart, reasons[#reasons + 1] = true, path
        end
    end
    if needsRestart and self.restart then
        self.counts.restart = self.counts.restart + 1
        table.sort(reasons)
        self.log('restarting the scene: ' .. table.concat(reasons, ', '))
        local scene = self.manager.stack[#self.manager.stack]
        if scene then
            local ok, message = pcall(self.restart, self.manager, scene)
            if not ok then
                self.manager.journal:record('Hot reload', tostring(message), nil, 'hotReload.restart')
            end
        end
    end
end

function HotReload:update(dt)
    self.clock = self.clock + dt
    if self.clock - (self.polled or 0) >= self.interval then
        self.polled = self.clock
        self:_poll()
        -- Scenes loaded from outside the watched roots (a game folder) join the watch list.
        local scene = self.manager.stack[#self.manager.stack]
        local root = scene and scene.package and scene.package.root
        if root and not self.watched[root] and not scene.package.archive then
            self:watch(root)
        end
        if self.clock - self.lastScan >= 5 then
            self.lastScan = self.clock
            self:rescan()
        end
    end
    if self.changedAt and self.clock - self.changedAt >= self.settle then
        self:_apply()
    end
end

return HotReload
