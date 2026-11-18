-- Bottom dock with two tabs. Assets: one browser for every file, with no mode switch. The first
-- screen offers two places: "Level files" (the level's own folder: import, create, rename, delete)
-- and "Project assets" (shared by all levels, read-only: use in place or copy into the level).
-- Locations: recent files, the autosave and saved locations. Objects are created from the Create
-- menu (Shift+A, the + button).
local Pointer = require('../../input.pointer')
local AssetStore = require('../../io.assetStore')
local Importer = require('../../core.importer')
local Menus = require('../support.menus')
local Kit = require('../support.kit')
local LevelFiles = require('../../io.levelFiles')
local LocationIO = require('../../io.locationIO')
local Models = require('source.engine.import.models')

local Browser = {}
Browser.__index = Browser

local TABS = { 'Assets', 'Location' }
local LABELS = { Assets = 'Assets', Location = 'Locations' }
local PROJECT = 'assets'
local HEAD = 30
local FOOT = 30

function Browser.create(state, ui, frame)
    local self = setmetatable({
        state = state,
        ui = ui,
        frame = frame,
        widgets = {},
        tab = 'Assets',
        view = 'level', -- 'level', 'project' or 'roots'
        levelPath = '',
        projectPath = PROJECT,
        menus = {},
        sources = {},
        drops = {},
        tabButtons = {},
        width = 600,
    }, Browser)
    for index, tab in ipairs(TABS) do
        local button = Kit.button(ui, frame, LABELS[tab], 96, 24, function()
            self:show(tab)
        end, 'tab')
        button.position = { 0, 6 + (index - 1) * 100, 0, 3 }
        self.tabButtons[tab] = button
    end
    self.pathBox = Kit.make(ui, 'TextBox', {
        position = { 0, 212, 0, 3 },
        size = { 1, -220, 0, 24 },
        fontSize = 13,
        text = '',
        visible = false,
        interactable = false,
    }, frame, 'field')
    self.nameBox = Kit.make(ui, 'TextBox', {
        position = { 0, 212, 0, 3 },
        size = { 0, 220, 0, 24 },
        fontSize = 13,
        text = '',
        placeholderText = 'file name',
        visible = false,
    }, frame, 'field')
    self.scroll = Kit.make(ui, 'ScrollFrame', {
        position = { 0, 4, 0, HEAD },
        size = { 1, -8, 1, -(HEAD + 4) },
        canvasSize = { 0, 0, 0, 0 },
        scrollBarThickness = 6,
    }, frame, 'list')
    -- Drag feedback, as in the object tree: the folder row that would receive the file is
    -- highlighted and a small label with the file name follows the pointer.
    self.markInto = Kit.make(ui, 'Frame', {
        size = { 1, 0, 0, 22 },
        visible = false,
        interactable = false,
        zIndex = 19,
    }, self.scroll, 'dropInto')
    self.ghost = Kit.make(ui, 'Frame', {
        size = { 0, 180, 0, 22 },
        visible = false,
        interactable = false,
        zIndex = 45,
    }, ui.content, 'window')
    self.ghostLabel = Kit.label(ui, self.ghost, '', {
        position = { 0, 8, 0, 2 },
        size = { 1, -16, 1, -4 },
        fontSize = 12,
    }, 'text')
    self.actions = Kit.make(ui, 'Frame', {
        position = { 0, 4, 1, -(FOOT) },
        size = { 1, -8, 0, 26 },
        backgroundTransparency = 1,
        visible = false,
    }, frame)
    self.dirty = true
    return self
end

function Browser:show(tab, importMode)
    -- Older names of the file tabs all mean the Assets tab.
    self.tab, self.dirty = (tab == 'Location') and 'Location' or 'Assets', true
    self.importMode = importMode == true
end

function Browser:openAssets()
    self.tab, self.dirty = 'Assets', true
end

-- The level folder an import goes into: the one on screen, or nil (a folder by file type).
function Browser:importFolder()
    if self.tab == 'Assets' and self.view == 'level' then
        return LevelFiles.clean(self.levelPath) or ''
    end
    return nil
end

-- Shows a freshly stored file in the Level files, so the author sees where an import went.
function Browser:reveal(stored, count)
    local relative = stored:sub(#LevelFiles.ROOT + 2)
    self.tab, self.view, self.dirty = 'Assets', 'level', true
    self.levelPath, self.levelSelected = LevelFiles.parent(relative), stored
    local more = (count or 1) > 1 and (' (+' .. (count - 1) .. ' more)') or ''
    self.state:notify('Imported into Level files: assets/' .. relative .. more)
end

function Browser:resize(width, height)
    self.width, self.height = width, height
    self.dirty = true
end

local function names(path)
    local result = { dirs = {}, files = {} }
    for _, name in ipairs(katsa.filesystem.getDirectoryItems(path)) do
        local full = path == '' and name or (path .. '/' .. name)
        if katsa.filesystem.getInfo(full, 'directory') then
            result.dirs[#result.dirs + 1] = { name = name, path = full }
        else
            result.files[#result.files + 1] = { name = name, path = full }
        end
    end
    return result
end

function Browser:clear()
    for _, widget in ipairs(self.widgets) do
        if not widget.destroyed then
            widget:destroy()
        end
    end
    self.widgets, self.menus, self.emptyMenu = {}, {}, nil
    self.sources, self.drops = {}, {}
end

function Browser:add(widget)
    self.widgets[#self.widgets + 1] = widget
    return widget
end

-- A row of the list tabs: a full-width button, optionally with an image thumbnail.
function Browser:row(y, label, onPress, selected, thumb, onMenu, onRelease)
    self.menus[math.floor(y / 22) + 1] = onMenu
    local x = 2
    if thumb then
        self:add(self.ui:create('ImageRect', {
            position = { 0, 2, 0, y + 2 },
            size = { 0, 18, 0, 18 },
            image = thumb,
            interactable = false,
        }, self.scroll))
        x = 24
    end
    local button = self:add(Kit.make(self.ui, 'Button', {
        position = { 0, x, 0, y },
        size = { 1, -(x + 2), 0, 22 },
        text = label,
        align = 'left',
        fontSize = 13,
    }, self.scroll, 'row', selected and 'selected' or nil))
    if onPress then
        button:connect('press', onPress)
    end
    if onRelease then
        button:connect('release', onRelease)
    end
    return y + 22
end

function Browser:heading(y, text)
    self:add(Kit.label(self.ui, self.scroll, text, { position = { 0, 6, 0, y }, size = { 1, -12, 0, 22 } }, 'muted'))
    return y + 22
end

-- Puts an asset in the scene: kind 'add' (model), 'sprite' or 'texture'; `fileKind` is its type.
function Browser:use(kind, stored, fileKind)
    Importer.place(self.state, stored, fileKind, kind)
end

function Browser:footer(specs)
    local x = 0
    for _, spec in ipairs(specs) do
        local button = self:add(Kit.button(self.ui, self.actions, spec[1], spec[3] or 100, 24, spec[2], 'tool'))
        button.position = { 0, x, 0, 0 }
        x = x + (spec[3] or 100) + 4
    end
    self.actions.visible = true
end

function Browser:ask(title, default, callback)
    self.state.panels.prompt:ask(title, default, callback)
end

function Browser:newFolder(path)
    self:ask('New folder', '', function(name)
        local made, message = LevelFiles.createFolder(path, name)
        if not made then
            self.state:notify(message)
        end
        self.dirty = true
    end)
end

function Browser:newFile(path)
    self:ask('New file name', 'notes.txt', function(name)
        local made, message = LevelFiles.createFile(path, name)
        if made then
            self.levelSelected = LevelFiles.full(made)
        else
            self.state:notify(message)
        end
        self.dirty = true
    end)
end

function Browser:rename(entry)
    local state = self.state
    self:ask('Rename ' .. entry.name, entry.name, function(name)
        local new, message = LevelFiles.rename(entry.path, name)
        if new then
            if self.levelSelected == entry.store then
                self.levelSelected = LevelFiles.full(new)
            end
            -- Objects keep the path they were given: tell the author instead of failing silently.
            state:notify('Renamed. Objects that used the old name show a placeholder until re-assigned')
        else
            state:notify(message)
        end
        self.dirty = true
    end)
end

-- Deletes after a confirmation: type the word to confirm (the prompt is the only modal we have).
function Browser:delete(entry)
    local state = self.state
    self:ask('Delete ' .. entry.name .. '? Type yes to confirm', '', function(answer)
        if answer:lower() ~= 'yes' then
            state:notify('Delete cancelled')
            return
        end
        local ok, message = LevelFiles.delete(entry.path)
        if ok then
            self.levelSelected = nil
            state:notify('Deleted ' .. entry.name)
        else
            state:notify(message)
        end
        self.dirty = true
    end)
end

-- Clipboard of the Level files: { entry, cut }. Paste copies, or moves when it was cut.
function Browser:setClipboard(entry, cut)
    self.clipboard = { path = entry.path, name = entry.name, cut = cut }
    self.state:notify((cut and 'Cut ' or 'Copied ') .. entry.name)
end

-- Where an object that moved is now: the open selection follows it.
local function follow(self, from, to)
    if self.levelSelected == LevelFiles.full(from) then
        self.levelSelected = LevelFiles.full(to)
    end
end

function Browser:paste(folder)
    local clip = self.clipboard
    if not clip then
        self.state:notify('Nothing to paste: use Cut or Copy on a file first')
        return
    end
    folder = LevelFiles.clean(folder) or ''
    local new, message
    if clip.cut then
        new, message = LevelFiles.move(clip.path, folder)
        if new then
            follow(self, clip.path, new)
            self.clipboard = nil
            self.state:notify('Moved ' .. clip.name .. '. Objects that used the old path show a placeholder until re-assigned')
        end
    else
        new, message = LevelFiles.copy(clip.path, folder)
        if new then
            self.state:notify('Pasted ' .. new)
        end
    end
    if not new then
        self.state:notify(tostring(message))
    end
    self.dirty = true
end

-- Clone: a copy next to the original (name_2).
function Browser:clone(entry)
    local new, message = LevelFiles.copy(entry.path, LevelFiles.parent(entry.path))
    self.state:notify(new and ('Cloned to ' .. new) or tostring(message))
    self.dirty = true
end

-- Move to a typed folder path (relative to Level files; empty = the root).
function Browser:moveTo(entry)
    self:ask('Move ' .. entry.name .. ' to folder (empty = root)', LevelFiles.parent(entry.path), function(folder)
        self:moveInto(entry, folder)
    end)
end

function Browser:moveInto(entry, folder)
    local new, message = LevelFiles.move(entry.path, folder)
    if new then
        follow(self, entry.path, new)
        self.state:notify('Moved to ' .. (folder ~= '' and folder or 'the root') .. '. Objects that used the old path show a placeholder until re-assigned')
    else
        self.state:notify(tostring(message))
    end
    self.dirty = true
end

-- Highlights the folder under the pointer (when a drop there is valid) and moves the name label.
function Browser:showDrag(drag, mx, my, index)
    if not (drag and drag.moved) then
        self.markInto.visible, self.ghost.visible = false, false
        return
    end
    local target = index and self.drops[index]
    local valid = target ~= nil and target ~= false and self.sources[index] ~= drag.entry
    self.markInto.visible = valid
    if valid then
        self.markInto.position = { 0, 0, 0, (index - 1) * 22 }
    end
    self.ghostLabel.text = (valid and 'Move to ' or '') .. tostring(drag.entry.name)
    self.ghost.position = { 0, mx + 14, 0, my + 18 }
    self.ghost.visible = true
end

-- Drag a row onto a folder row (or ".." for the parent folder) to move it. The press is noted,
-- the release decides; a drag shorter than a few pixels is an ordinary click.
function Browser:pollDrag()
    local down = Pointer.isDown(1)
    local state = self.state
    local mx, my = state:pointer()
    local _, sy = self.scroll:getAbsolutePosition()
    local inside = self.view == 'level' and self.tab == 'Assets' and self.frame.visible
    local index = inside and math.floor((my - sy + (self.scroll.scrollY or 0)) / 22) + 1 or nil
    if down and not self.wasLeft then
        local source = index and self.sources[index]
        self.drag = source and { entry = source, x = mx, y = my, moved = false } or nil
        self.dragMoved = false
    elseif down and self.drag then
        if math.abs(mx - self.drag.x) + math.abs(my - self.drag.y) > 8 then
            self.drag.moved, self.dragMoved = true, true
        end
        self:showDrag(self.drag, mx, my, index)
    elseif not down and self.wasLeft and self.drag then
        local drag = self.drag
        self.drag = nil
        self:showDrag(nil)
        local target = drag.moved and index and self.drops[index]
        if target ~= nil and target ~= false then
            self:moveInto(drag.entry, target)
        end
    end
    self.wasLeft = down
end

-- Copies a project file into the level folder on screen (or the folder for its type).
function Browser:copyToLevel(entry)
    local stored, result = Importer.copy(entry.path, LevelFiles.clean(self.levelPath))
    if stored then
        self:reveal(stored)
    else
        self.state:notify(tostring(result))
    end
end

-- The use of a project file in place: a shared:// reference, so nothing is copied.
function Browser.sharedUrl(entry)
    return 'shared://' .. entry.path:gsub('^assets/', '')
end

-- First screen: the two places.
function Browser:buildRoots()
    self.pathBox.text = 'Assets'
    local y = self:heading(0, 'Choose where to look')
    y = self:row(y, '[Level files]   this level\'s own folder: import here, create, rename, delete', function()
        self.view, self.dirty = 'level', true
    end)
    y = self:row(y, '[Project assets]   shared by all levels, read-only: use in place or copy into the level', function()
        self.view, self.projectPath, self.dirty = 'project', PROJECT, true
    end)
    self.scroll.canvasSize = { 0, 0, 0, y }
end

function Browser:buildLevel()
    local state = self.state
    local path = LevelFiles.clean(self.levelPath) or ''
    local listing = LevelFiles.list(path)
    self.pathBox.text = 'Level files / ' .. (path ~= '' and path or '(root)')
    local y = self:row(0, '..', function()
        if path == '' then
            self.view = 'roots'
        else
            self.levelPath, self.levelSelected = LevelFiles.parent(path), nil
        end
        self.dirty = true
    end)
    if path ~= '' then
        self.drops[1] = LevelFiles.parent(path)
    end
    local function menu(entry)
        return function(x, my)
            self.levelSelected, self.dirty = entry.store, true
            state:popup(Menus.levelEntry(state, self, entry), x, my, { width = 230 })
        end
    end
    for _, dir in ipairs(listing.dirs) do
        local index = math.floor(y / 22) + 1
        self.sources[index], self.drops[index] = dir, dir.path
        -- A folder opens on release so that pressing it can start a drag instead.
        y = self:row(y, '[' .. dir.name .. ']', nil, nil, nil, menu(dir), function()
            if not self.dragMoved then
                self.levelPath, self.levelSelected, self.dirty = dir.path, nil, true
            end
        end)
    end
    for _, file in ipairs(listing.files) do
        local kind = AssetStore.kind(file.store, Models.supports)
        local label = file.name .. (kind ~= 'file' and ('   (' .. kind .. ')') or '')
        self.sources[math.floor(y / 22) + 1] = file
        y = self:row(y, label, function()
            self.levelSelected, self.dirty = file.store, true
        end, self.levelSelected == file.store, kind == 'image' and file.store or nil, menu(file))
    end
    if #listing.dirs + #listing.files == 0 then
        y = self:heading(y, 'This folder is empty. Press Import... or drop files on the window.')
    end
    self.scroll.canvasSize = { 0, 0, 0, y }
    local function selectedEntry()
        for _, group in ipairs({ listing.dirs, listing.files }) do
            for _, entry in ipairs(group) do
                if entry.store == self.levelSelected then
                    return entry
                end
            end
        end
    end
    local function withFile(action)
        return function()
            local entry = selectedEntry()
            if entry then
                action(entry)
            else
                state:notify('Select a file first (right-click a folder to rename or delete it)')
            end
        end
    end
    -- Right-click on empty space: the New menu.
    self.emptyMenu = function(x, my)
        state:popup(Menus.levelNew(state, self, path), x, my, { width = 220 })
    end
    self:footer({
        { 'Import...', function()
            Importer.dialog(state)
        end },
        { 'New', function()
            -- The list opens above the pointer: the dock is at the bottom of the window.
            local x, y = state:pointer()
            state:popup(Menus.levelNew(state, self, path), x - 20, y - 90, { width = 200 })
        end, 80 },
        { 'Add to level', withFile(function(entry)
            local kind = AssetStore.kind(entry.store, Models.supports)
            self:use(kind == 'image' and 'sprite' or 'add', entry.store, kind)
        end), 110 },
    })
end

function Browser:buildProject()
    local state = self.state
    local path = self.projectPath
    local listing = names(path)
    self.pathBox.text = 'Project assets / ' .. path:gsub('^assets/?', '')
    local y = self:row(0, '..', function()
        if path == PROJECT then
            self.view = 'roots'
        else
            self.projectPath = path:match('^(.*)/[^/]+$') or PROJECT
        end
        self.selected, self.dirty = nil, true
    end)
    for _, dir in ipairs(listing.dirs) do
        y = self:row(y, '[' .. dir.name .. ']', function()
            self.projectPath, self.selected, self.dirty = dir.path, nil, true
        end)
    end
    for _, file in ipairs(listing.files) do
        local kind = AssetStore.kind(file.path, Models.supports)
        local function select()
            self.selected, self.dirty = file, true
        end
        y = self:row(y, file.name .. (kind ~= 'file' and ('   (' .. kind .. ')') or ''), select,
            self.selected and self.selected.path == file.path, kind == 'image' and file.path or nil,
            function(x, my)
                select()
                state:popup(Menus.projectEntry(state, self, file, kind), x, my, { width = 250 })
            end)
    end
    self.scroll.canvasSize = { 0, 0, 0, y }
    local function withFile(action)
        return function()
            local file = self.selected
            if file then
                action(file, AssetStore.kind(file.path, Models.supports))
            else
                state:notify('Select a file first')
            end
        end
    end
    self:footer({
        { 'Add to level', withFile(function(file, kind)
            self:use(kind == 'image' and 'sprite' or 'add', Browser.sharedUrl(file), kind)
        end), 110 },
        { 'Copy to level files', withFile(function(file)
            self:copyToLevel(file)
        end), 150 },
    })
end

function Browser:buildLocation()
    local state = self.state
    self.nameBox.text = state.fileName or ''
    -- In import mode a click adds the file's objects to the level; otherwise it opens the file.
    local function choose(path)
        if self.importMode then
            state:importLocation(path)
        else
            state:openLocation(path)
        end
        self.dirty = true
    end
    local y = 0
    if self.importMode then
        y = self:heading(y, 'Import: click a .katsa file to add its objects to the level')
    end
    y = self:heading(y, 'Recent')
    for _, path in ipairs(state.recent or {}) do
        y = self:row(y, path, function()
            choose(path)
        end, nil, nil, function(x, my)
            state:popup(Menus.location(state, self, path), x, my, { width = 220 })
        end)
    end
    y = self:heading(y, 'Autosave')
    y = self:row(y, LocationIO.AUTOSAVE, function()
        choose(LocationIO.AUTOSAVE)
    end, nil, nil, function(x, my)
        state:popup(Menus.location(state, self, LocationIO.AUTOSAVE), x, my, { width = 220 })
    end)
    for _, folder in ipairs({ LocationIO.FOLDER, LocationIO.EXPORTS }) do
        y = self:heading(y, tostring(katsa.filesystem.getSaveDirectory()) .. '/' .. folder)
        for _, name in ipairs(katsa.filesystem.getDirectoryItems(folder)) do
            if name:match('%.katsa$') then
                local full = folder .. '/' .. name
                y = self:row(y, name, function()
                    choose(full)
                end, nil, nil, function(x, my)
                    state:popup(Menus.location(state, self, full), x, my, { width = 220 })
                end)
            end
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, y }
    self:footer({
        { 'Save', function()
            state:saveLocation(self.nameBox.text ~= '' and self.nameBox.text or nil)
            self.dirty = true
        end },
        { 'New', function()
            state:clearLevel()
            state.fileName, state.savedVersion = nil, state.undo.version
            state:notify('New empty location')
            self.dirty = true
        end },
    })
end

-- Right button on a row: the row's menu. Rows are 22 px and the list is polled, so no per-row
-- signal is needed.
function Browser:pollMenu()
    local down = Pointer.isDown(2)
    local pressed = down and not self.wasRight
    self.wasRight = down
    local state = self.state
    if not pressed or state.panels.popup:isOpen() or not self.frame.visible then
        return
    end
    local ui = self.ui
    local hit = ui:hit(Pointer.getX(), Pointer.getY())
    while hit and hit ~= self.scroll do
        hit = hit.parent
    end
    if not hit then
        return
    end
    local mx, my = state:pointer()
    local _, sy = self.scroll:getAbsolutePosition()
    local index = math.floor((my - sy + (self.scroll.scrollY or 0)) / 22) + 1
    local onMenu = self.menus[index] or self.emptyMenu
    if onMenu then
        onMenu(mx, my)
    end
end

function Browser:update()
    self:pollMenu()
    self:pollDrag()
    if not self.dirty then
        return
    end
    self.dirty = false
    self:clear()
    for name, button in pairs(self.tabButtons) do
        if name == self.tab then
            button:addTag('selected')
        else
            button:removeTag('selected')
        end
    end
    self.pathBox.visible = self.tab == 'Assets'
    self.nameBox.visible = self.tab == 'Location'
    self.actions.visible = false
    self.scroll.size = { 1, -8, 1, -(HEAD + 4 + FOOT) }
    if self.tab == 'Assets' then
        if self.view == 'roots' then
            self:buildRoots()
        elseif self.view == 'project' then
            self:buildProject()
        else
            self:buildLevel()
        end
    else
        self:buildLocation()
    end
    local styler = self.state.styler
    styler:apply(self.frame)
end

return Browser
