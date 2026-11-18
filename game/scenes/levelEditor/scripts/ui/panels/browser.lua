-- Bottom panel: the Create tab (primitives, lights, objects) and the Files tab, a browser over
-- the virtual file system (project folders and the save directory). A model file is imported
-- into the editor's asset store and placed; an image becomes a sprite quad or the colour map of
-- the selected mesh. Image rows show a thumbnail.
local AssetStore = require('../../io.assetStore')
local Catalog = require('../../builders.catalog')
local Models = require('source.engine.import.models')
local Theme = require('../theme')

local Browser = {}
Browser.__index = Browser

local CELL_W, CELL_H = 110, 26

function Browser.create(state, ui)
    local self = setmetatable({ state = state, ui = ui, widgets = {}, tab = 'Create', path = '' }, Browser)
    self.frame = ui:container({
        name = 'BrowserPanel',
        position = { 0, Theme.left, 1, -(Theme.bottom + Theme.browser) },
        size = { 1, -(Theme.left + Theme.right), 0, Theme.browser },
        backgroundColor = Theme.panel,
        zIndex = 5,
    }, ui.content)
    for index, tab in ipairs({ 'Create', 'Files' }) do
        local button = ui:button({
            position = { 0, 6 + (index - 1) * 84, 0, 4 },
            size = { 0, 80, 0, 22 },
            text = tab,
            fontSize = 13,
            backgroundColor = Theme.button,
        }, self.frame)
        button:connect('press', function()
            self.tab, self.dirty = tab, true
        end)
    end
    self.pathBox = ui:create('TextBox', {
        position = { 0, 180, 0, 4 },
        size = { 1, -300, 0, 22 },
        fontSize = 13,
        text = '',
        backgroundColor = Theme.field,
        placeholderText = 'folder (empty = root), Enter opens it',
        visible = false,
    }, self.frame)
    self.pathBox:connect('submitted', function(_, text)
        self.path, self.selected, self.dirty = text:gsub('^/+', ''):gsub('/+$', ''), nil, true
    end)
    self.scroll = ui:scroll({
        position = { 0, 4, 0, 30 },
        size = { 1, -8, 1, -62 },
        canvasSize = { 0, 0, 0, 0 },
        scrollBarThickness = 6,
        backgroundColor = Theme.bar,
    }, self.frame)
    self.actions = ui:container({
        position = { 0, 4, 1, -30 },
        size = { 1, -8, 0, 26 },
        backgroundTransparency = 1,
    }, self.frame)
    self.dirty = true
    return self
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

function Browser:buildCreate()
    local ui, state = self.ui, self.state
    local y, row = 0, nil
    local lastGroup
    local x = 0
    for _, item in ipairs(Catalog.items()) do
        if item.group ~= lastGroup then
            lastGroup = item.group
            y = y + (row and CELL_H + 4 or 0)
            x, row = 0, true
            self:add(ui:create('Label', {
                position = { 0, 6, 0, y },
                size = { 0, 90, 0, CELL_H },
                fontSize = 13,
                align = 'left',
                text = item.group,
                textColor = Theme.dim,
                interactable = false,
            }, self.scroll))
            x = 96
        end
        local button = self:add(ui:button({
            position = { 0, x, 0, y },
            size = { 0, CELL_W - 4, 0, CELL_H - 2 },
            text = item.label,
            fontSize = 13,
            backgroundColor = Theme.button,
        }, self.scroll))
        button:connect('press', function()
            local ok, message = pcall(item.make, state, state:placement())
            if not ok then
                state:notify(tostring(message))
            end
        end)
        x = x + CELL_W
    end
    self.scroll.canvasSize = { 0, 0, 0, y + CELL_H + 4 }
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
            name = require('source.engine.nodes.core.clone').uniqueName(state.scene.world, 'Sprite'),
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

function Browser:buildFiles()
    local ui = self.ui
    self.pathBox.text = self.path
    local listing = names(self.path)
    local y = 0
    local function row(label, thumb, onPress, selected)
        local x = 0
        if thumb then
            self:add(ui:create('ImageRect', {
                position = { 0, 2, 0, y + 2 },
                size = { 0, 18, 0, 18 },
                image = thumb,
                interactable = false,
            }, self.scroll))
            x = 22
        end
        local button = self:add(ui:button({
            position = { 0, x, 0, y },
            size = { 1, -x, 0, 22 },
            text = label,
            align = 'left',
            fontSize = 13,
            backgroundColor = selected and Theme.rowSelected or Theme.row_,
            textColor = Theme.text,
        }, self.scroll))
        button:connect('press', onPress)
        y = y + 22
    end
    if self.path ~= '' then
        row('..', nil, function()
            self.path, self.selected, self.dirty = self.path:match('^(.*)/[^/]+$') or '', nil, true
        end)
    end
    for _, dir in ipairs(listing.dirs) do
        row('[' .. dir.name .. ']', nil, function()
            self.path, self.selected, self.dirty = dir.path, nil, true
        end)
    end
    for _, file in ipairs(listing.files) do
        local kind = AssetStore.kind(file.path, Models.supports)
        if kind then
            local isSelected = self.selected and self.selected.path == file.path
            row(file.name .. (kind == 'model' and '   (model)' or ''), kind == 'image' and file.path or nil, function()
                self.selected, self.dirty = file, true
            end, isSelected)
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, y }
    local x = 0
    for _, spec in ipairs({
        { 'Add model', 'add' },
        { 'Sprite quad', 'sprite' },
        { 'Use as texture', 'texture' },
    }) do
        local button = self:add(ui:button({
            position = { 0, x, 0, 0 },
            size = { 0, 110, 0, 24 },
            text = spec[1],
            fontSize = 13,
            backgroundColor = Theme.button,
        }, self.actions))
        button:connect('press', function()
            self:act(spec[2])
        end)
        x = x + 114
    end
end

function Browser:update()
    if not self.dirty then
        return
    end
    self.dirty = false
    self:clear()
    self.pathBox.visible = self.tab == 'Files'
    if self.tab == 'Create' then
        self:buildCreate()
    else
        self:buildFiles()
    end
end

return Browser
