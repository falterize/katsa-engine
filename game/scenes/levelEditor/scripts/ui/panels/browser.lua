-- Bottom dock with tabs. Create: primitives, lights and objects (buttons wrap to the dock width).
-- Files: a browser over the virtual file system; a model is imported into the editor's asset store
-- and placed, an image becomes a sprite quad or the colour map of the selected mesh, with a
-- thumbnail per image row. Location: recent files, the autosave and saved locations.
local AssetStore = require('../../io.assetStore')
local Catalog = require('../../builders.catalog')
local Clone = require('source.engine.nodes.core.clone')
local Flow = require('../flow')
local Kit = require('../kit')
local LocationIO = require('../../io.locationIO')
local Models = require('source.engine.import.models')

local Browser = {}
Browser.__index = Browser

local TABS = { 'Create', 'Files', 'Location' }
local HEAD = 30
local FOOT = 30

function Browser.create(state, ui, frame)
    local self = setmetatable({
        state = state,
        ui = ui,
        frame = frame,
        widgets = {},
        tab = 'Create',
        path = '',
        tabButtons = {},
        width = 600,
    }, Browser)
    for index, tab in ipairs(TABS) do
        local button = Kit.button(ui, frame, tab, 80, 24, function()
            self:show(tab)
        end, 'tab')
        button.position = { 0, 6 + (index - 1) * 84, 0, 3 }
        self.tabButtons[tab] = button
    end
    self.pathBox = Kit.make(ui, 'TextBox', {
        position = { 0, 262, 0, 3 },
        size = { 1, -270, 0, 24 },
        fontSize = 13,
        text = '',
        placeholderText = 'folder (empty = root), Enter opens it',
        visible = false,
    }, frame, 'field')
    self.pathBox:connect('submitted', function(_, text)
        self.path, self.selected, self.dirty = text:gsub('^/+', ''):gsub('/+$', ''), nil, true
    end)
    self.nameBox = Kit.make(ui, 'TextBox', {
        position = { 0, 262, 0, 3 },
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
    self.widgets = {}
end

function Browser:add(widget)
    self.widgets[#self.widgets + 1] = widget
    return widget
end

-- A row of the list tabs: a full-width button, optionally with an image thumbnail.
function Browser:row(y, label, onPress, selected, thumb)
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

function Browser:buildCreate()
    local state = self.state
    local items = Catalog.items()
    local y, group, list = 0, nil, {}
    local function flush()
        if #list == 0 then
            return
        end
        local positions, height = Flow.place(list, self.width - 24, 4, 24, 0)
        for index, entry in ipairs(list) do
            entry.button.position = { 0, 8 + positions[index].x, 0, y + positions[index].y }
        end
        y = y + height + 8
        list = {}
    end
    for _, item in ipairs(items) do
        if item.group ~= group then
            flush()
            group = item.group
            y = self:heading(y, group)
        end
        local width = math.max(60, #item.label * 8 + 22)
        local button = self:add(Kit.button(self.ui, self.scroll, item.label, width, 24, function()
            local ok, message = pcall(item.make, state, state:placement())
            if not ok then
                state:notify(tostring(message))
            end
        end, 'tool'))
        list[#list + 1] = { w = width, button = button }
    end
    flush()
    self.scroll.canvasSize = { 0, 0, 0, y }
end

function Browser:act(kind)
    local state, file = self.state, self.selected
    if not file then
        state:notify('Select a file first')
        return
    end
    local stored, fileKind = AssetStore.import(file.path, Models.supports)
    if not stored then
        state:notify(tostring(fileKind))
        return
    end
    local position = state:placement()
    if fileKind == 'model' and kind == 'add' then
        local ok, message = pcall(state.ops.placeModel, state.ops, stored, { position[1], position[2], position[3] })
        if not ok then
            state:notify('Cannot load the model: ' .. tostring(message))
        end
    elseif fileKind == 'image' and kind == 'sprite' then
        local mesh = state.ops:create('Mesh3D', {
            name = Clone.uniqueName(state.world, 'Sprite'),
            kind = 'quad',
            position = { position[1], position[2] + 1, position[3] },
            size = { 2, 2, 1 },
        })
        state.ops:applyTexture(mesh, stored)
    elseif fileKind == 'image' and kind == 'texture' then
        local target = state.selection:primary()
        if target and target.className == 'Mesh3D' then
            state.ops:applyTexture(target, stored)
        else
            state:notify('Select a mesh to texture')
        end
    else
        state:notify('That action does not fit this file type')
    end
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
        if kind then
            local isSelected = self.selected and self.selected.path == file.path
            y = self:row(y, file.name .. (kind == 'model' and '   (model)' or ''), function()
                self.selected, self.dirty = file, true
            end, isSelected, kind == 'image' and file.path or nil)
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, y }
    self:footer({
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
        end)
    end
    y = self:heading(y, 'Autosave')
    y = self:row(y, LocationIO.AUTOSAVE, function()
        choose(LocationIO.AUTOSAVE)
    end)
    for _, folder in ipairs({ LocationIO.FOLDER, LocationIO.EXPORTS }) do
        y = self:heading(y, tostring(katsa.filesystem.getSaveDirectory()) .. '/' .. folder)
        for _, name in ipairs(katsa.filesystem.getDirectoryItems(folder)) do
            if name:match('%.katsa$') then
                y = self:row(y, name, function()
                    choose(folder .. '/' .. name)
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

function Browser:update()
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
    self.pathBox.visible = self.tab == 'Files'
    self.nameBox.visible = self.tab == 'Location'
    self.actions.visible = false
    local footer = self.tab ~= 'Create'
    self.scroll.size = { 1, -8, 1, -(HEAD + 4 + (footer and FOOT or 0)) }
    if self.tab == 'Create' then
        self:buildCreate()
    elseif self.tab == 'Files' then
        self:buildFiles()
    else
        self:buildLocation()
    end
    local styler = self.state.styler
    styler:apply(self.frame)
end

return Browser
