-- Bottom dock with tabs (objects are created from the Create menu: Shift+A, the + button).
-- Level: the files of the open level (editor/assets in the save directory: everything imported
-- lands here) with new folder/file, rename and delete. Import (internal name Files): a browser over the virtual file system; a model is imported into the editor's asset store
-- and placed, an image becomes a sprite quad or the colour map of the selected mesh, with a
-- thumbnail per image row. Location: recent files, the autosave and saved locations.
local AssetStore = require('../../io.assetStore')
local Importer = require('../../core.importer')
local Clone = require('source.engine.nodes.core.clone')
local Menus = require('../support.menus')
local Kit = require('../support.kit')
local LevelFiles = require('../../io.levelFiles')
local LocationIO = require('../../io.locationIO')
local Models = require('source.engine.import.models')

local Browser = {}
Browser.__index = Browser

local TABS = { 'Level', 'Files', 'Location' }
local LABELS = { Level = 'Level files', Files = 'Import', Location = 'Locations' }
local HEAD = 30
local FOOT = 30

function Browser.create(state, ui, frame)
    local self = setmetatable({
        state = state,
        ui = ui,
        frame = frame,
        widgets = {},
        tab = 'Level',
        levelPath = '',
        menus = {},
        path = '',
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
        position = { 0, 312, 0, 3 },
        size = { 1, -320, 0, 24 },
        fontSize = 13,
        text = '',
        placeholderText = 'folder (empty = root), Enter opens it',
        visible = false,
    }, frame, 'field')
    self.pathBox:connect('submitted', function(_, text)
        self.path, self.selected, self.dirty = text:gsub('^/+', ''):gsub('/+$', ''), nil, true
    end)
    self.nameBox = Kit.make(ui, 'TextBox', {
        position = { 0, 312, 0, 3 },
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
    self.tab, self.dirty = tab, true
    self.importMode = importMode == true
end

-- Shows the level's own files (the folder imports are copied into) in the Level tab.
function Browser:openSceneFolder()
    katsa.filesystem.createDirectory('editor')
    katsa.filesystem.createDirectory(AssetStore.ROOT)
    self.tab, self.levelPath, self.levelSelected, self.dirty = 'Level', '', nil, true
    self.state:notify(('Level files: %s/%s'):format(katsa.filesystem.getSaveDirectory(), AssetStore.ROOT))
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
    self.widgets, self.menus = {}, {}
end

function Browser:add(widget)
    self.widgets[#self.widgets + 1] = widget
    return widget
end

-- A row of the list tabs: a full-width button, optionally with an image thumbnail.
function Browser:row(y, label, onPress, selected, thumb, onMenu)
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
    button:connect('press', onPress)
    return y + 22
end

function Browser:heading(y, text)
    self:add(Kit.label(self.ui, self.scroll, text, { position = { 0, 6, 0, y }, size = { 1, -12, 0, 22 } }, 'muted'))
    return y + 22
end

-- Imports the selected file of the Import tab into the level files, then uses it.
function Browser:act(kind)
    if not self.selected then
        self.state:notify('Select a file first')
        return
    end
    local ok, stored = Importer.import(self.state, self.selected.path, kind)
    if ok and type(stored) == 'string' and stored:sub(1, #LevelFiles.ROOT) == LevelFiles.ROOT then
        self:reveal(stored)
    end
end

-- Makes the Level tab show `stored` (a store path) so the author can see where an import went.
function Browser:reveal(stored)
    local relative = stored:sub(#LevelFiles.ROOT + 2)
    self.levelPath = LevelFiles.parent(relative)
    self.levelSelected = stored
    self.dirty = true
    self.state:notify('Saved as assets/' .. relative)
end

-- Uses an asset that is already in the level files (a model into the level, an image as a
-- sprite quad or the colour map of the selected mesh).
function Browser:use(kind, stored, fileKind)
    Importer.place(self.state, stored, fileKind, kind)
end

function Browser:footer(specs)
    local x = 0
    for _, spec in ipairs(specs) do
        local button = self:add(Kit.button(self.ui, self.actions, spec[1], spec[3] or 110, 24, spec[2], 'tool'))
        button.position = { 0, x, 0, 0 }
        x = x + (spec[3] or 110) + 4
    end
    self.actions.visible = true
end

-- The Level tab: the files of this level, with folders, rename and delete.
function Browser:buildLevel()
    local state = self.state
    local path = LevelFiles.clean(self.levelPath) or ''
    local listing = LevelFiles.list(path)
    self.pathBox.text = 'assets' .. (path ~= '' and ('/' .. path) or '')
    local y = 0
    if path ~= '' then
        y = self:row(y, '..', function()
            self.levelPath, self.levelSelected, self.dirty = LevelFiles.parent(path), nil, true
        end)
    end
    local function menu(entry)
        return function(x, my)
            self.levelSelected, self.dirty = entry.store, true
            state:popup(Menus.levelEntry(state, self, entry), x, my, { width = 230 })
        end
    end
    for _, dir in ipairs(listing.dirs) do
        y = self:row(y, '[' .. dir.name .. ']', function()
            self.levelPath, self.levelSelected, self.dirty = dir.path, nil, true
        end, nil, nil, menu(dir))
    end
    for _, file in ipairs(listing.files) do
        local kind = AssetStore.kind(file.store, Models.supports)
        local label = file.name .. (kind == 'model' and '   (model)' or '')
        y = self:row(y, label, function()
            self.levelSelected, self.dirty = file.store, true
        end, self.levelSelected == file.store, kind == 'image' and file.store or nil, menu(file))
    end
    if #listing.dirs + #listing.files == 0 then
        y = self:heading(y, 'Empty. Import files, or create a folder or a file below.')
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
    self:footer({
        { 'New folder', function()
            self:ask('New folder', '', function(name)
                local made, message = LevelFiles.createFolder(path, name)
                if not made then
                    state:notify(message)
                end
                self.dirty = true
            end)
        end },
        { 'New file', function()
            self:ask('New file name', 'notes.txt', function(name)
                local made, message = LevelFiles.createFile(path, name)
                if made then
                    self.levelSelected = LevelFiles.full(made)
                else
                    state:notify(message)
                end
                self.dirty = true
            end)
        end },
        { 'Rename', function()
            local entry = selectedEntry()
            if entry then
                self:rename(entry)
            else
                state:notify('Select a file first (right-click a folder to rename it)')
            end
        end },
        { 'Delete', function()
            local entry = selectedEntry()
            if entry then
                self:delete(entry)
            else
                state:notify('Select a file first (right-click a folder to delete it)')
            end
        end },
        { 'Import...', function()
            self:show('Files')
        end },
    })
end

function Browser:ask(title, default, callback)
    self.state.panels.prompt:ask(title, default, callback)
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

function Browser:buildFiles()
    local listing = names(self.path)
    local y = 0
    self.pathBox.text = self.path
    if self.path ~= '' then
        y = self:row(y, '..', function()
            self.path, self.selected, self.dirty = self.path:match('^(.*)/[^/]+$') or '', nil, true
        end)
    end
    for _, dir in ipairs(listing.dirs) do
        y = self:row(y, '[' .. dir.name .. ']', function()
            self.path, self.selected, self.dirty = dir.path, nil, true
        end)
    end
    for _, file in ipairs(listing.files) do
        local kind = AssetStore.kind(file.path, Models.supports)
        do
            local isSelected = self.selected and self.selected.path == file.path
            y = self:row(y, file.name .. (kind == 'model' and '   (model)' or ''), function()
                self.selected, self.dirty = file, true
            end, isSelected, kind == 'image' and file.path or nil, function(x, y)
                self.selected, self.dirty = file, true
                self.state:popup(Menus.asset(self.state, self, file, kind), x, y, { width = 240 })
            end)
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, y }
    self:footer({
        { 'Import files...', function()
            Importer.dialog(self.state)
        end, 120 },
        { 'Add model', function()
            self:act('add')
        end },
        { 'Sprite quad', function()
            self:act('sprite')
        end },
        { 'Use as texture', function()
            self:act('texture')
        end, 120 },
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
    local down = katsa.mouse.isDown(2)
    local pressed = down and not self.wasRight
    self.wasRight = down
    local state = self.state
    if not pressed or state.panels.popup:isOpen() or not self.frame.visible then
        return
    end
    local ui = self.ui
    local hit = ui:hit(katsa.mouse.getX(), katsa.mouse.getY())
    while hit and hit ~= self.scroll do
        hit = hit.parent
    end
    if not hit then
        return
    end
    local mx, my = state:pointer()
    local _, sy = self.scroll:getAbsolutePosition()
    local index = math.floor((my - sy + (self.scroll.scrollY or 0)) / 22) + 1
    local onMenu = self.menus[index]
    if onMenu then
        onMenu(mx, my)
    end
end

function Browser:update()
    self:pollMenu()
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
    self.pathBox.visible = self.tab == 'Files' or self.tab == 'Level'
    self.pathBox.interactable = self.tab == 'Files'
    self.nameBox.visible = self.tab == 'Location'
    self.actions.visible = false
    self.scroll.size = { 1, -8, 1, -(HEAD + 4 + FOOT) }
    if self.tab == 'Level' then
        self:buildLevel()
    elseif self.tab == 'Files' then
        self:buildFiles()
    else
        self:buildLocation()
    end
    local styler = self.state.styler
    styler:apply(self.frame)
end

return Browser
