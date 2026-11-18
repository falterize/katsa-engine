-- The menu bar content (File, Edit, Create, View, Settings). Every menu is a function that returns
-- its items fresh each time it opens, so check marks, the recent list and enabled states are
-- current. An item is { label, run, shortcut, checked, enabled } or { separator = true } or
-- { heading = text }.
local Catalog = require('../builders.catalog')
local Shortcut = require('./shortcut')

local Menus = {}

local function shortcut(state, action)
    return Shortcut.of(state.scene.input.map, action)
end

local function item(label, run, extra)
    local entry = extra or {}
    entry.label, entry.run = label, run
    return entry
end

local SEPARATOR = { separator = true }

local function file(state)
    local items = {
        item('New location', function()
            state:newLocation()
        end),
        item('Open...', function()
            state.panels.browser:show('Location', false)
        end),
    }
    local recent = state.recent or {}
    if #recent > 0 then
        items[#items + 1] = { heading = 'Recent' }
        for index = 1, math.min(5, #recent) do
            local path = recent[index]
            items[#items + 1] = item(path:match('([^/]+)$') or path, function()
                state:openLocation(path)
            end)
        end
    end
    items[#items + 1] = SEPARATOR
    items[#items + 1] = item('Save', function()
        state:saveLocation()
    end, { shortcut = shortcut(state, 'editorSave') })
    items[#items + 1] = item('Save as...', function()
        state.panels.prompt:ask('Save as', state.fileName or 'untitled', function(name)
            state:saveLocation(name)
        end)
    end)
    items[#items + 1] = SEPARATOR
    items[#items + 1] = item('Import .katsa...', function()
        state.panels.browser:show('Location', true)
    end)
    items[#items + 1] = item('Export .katsa...', function()
        state.panels.prompt:ask('Export as .katsa', state.fileName or 'location', function(name)
            state:exportLocation(name)
        end)
    end)
    return items
end

local function edit(state)
    local ops, selection = state.ops, state.selection
    local has = selection:count() > 0
    return {
        item('Undo', function()
            state.undo:undo()
            state:refresh()
        end, { shortcut = shortcut(state, 'editorUndo'), enabled = state.undo:canUndo() }),
        item('Redo', function()
            state.undo:redo()
            state:refresh()
        end, { shortcut = shortcut(state, 'editorRedo'), enabled = state.undo:canRedo() }),
        SEPARATOR,
        item('Copy', function()
            state:notify(('Copied %d'):format(ops:copy(selection:items())))
        end, { shortcut = shortcut(state, 'editorCopy'), enabled = has }),
        item('Paste', function()
            ops:paste(state.level)
        end, { shortcut = shortcut(state, 'editorPaste') }),
        item('Duplicate', function()
            ops:duplicate(selection:items())
        end, { shortcut = shortcut(state, 'editorDuplicate'), enabled = has }),
        item('Delete', function()
            ops:delete(selection:items())
        end, { shortcut = shortcut(state, 'editorDelete'), enabled = has }),
        SEPARATOR,
        item('Select all', function()
            state:selectAll()
        end, { shortcut = shortcut(state, 'editorSelectAll') }),
        item('Group', function()
            ops:group(selection:items())
        end, { enabled = has }),
        item('Ungroup', function()
            local node = selection:primary()
            local ok, message = ops:ungroup(node)
            if not ok then
                state:notify(message)
            end
        end, { enabled = has }),
    }
end

local function create(state)
    local items, group = {}, nil
    for _, entry in ipairs(Catalog.items()) do
        if entry.group ~= group then
            group = entry.group
            items[#items + 1] = { heading = group }
        end
        items[#items + 1] = item(entry.label, function()
            local ok, message = pcall(entry.make, state, state:placement())
            if not ok then
                state:notify(tostring(message))
            end
        end)
    end
    items[#items + 1] = SEPARATOR
    items[#items + 1] = item('Import model or image...', function()
        state.panels.browser:show('Files')
    end)
    return items
end

local function view(state)
    local environment = state.world.environment
    return {
        item('Grid', function()
            state.grid:setVisible(not state.grid.visible)
            state:savePrefs()
        end, { checked = state.grid.visible, shortcut = shortcut(state, 'editorToggleGrid') }),
        item('Light and camera gizmos', function()
            environment.debug.gizmos.enabled = not environment.debug.gizmos.enabled
        end, { checked = environment.debug.gizmos.enabled }),
        item('Shadows', function()
            environment.shadows.enabled = not environment.shadows.enabled
        end, { checked = environment.shadows.enabled }),
        item('Wireframe', function()
            environment.debug.wireframe = not environment.debug.wireframe
        end, { checked = environment.debug.wireframe }),
        SEPARATOR,
        item('Frame selection', function()
            local items = state.selection:items()
            state:frame(#items > 0 and items or state.level.children)
        end, { shortcut = shortcut(state, 'editorFocus') }),
        item('Frame all', function()
            state:frame(state.level.children)
        end, { shortcut = shortcut(state, 'editorFrameAll') }),
        SEPARATOR,
        item('Reset panel layout', function()
            state.dock:setSizes({ left = 250, right = 320, bottom = 190 })
            state:savePrefs()
        end),
    }
end

local function settings(state)
    return {
        item('Editor settings...', function()
            state.panels.settings:open_('Appearance')
        end),
        item('Keyboard shortcuts...', function()
            state.panels.settings:open_('Shortcuts')
        end),
        SEPARATOR,
        item('Dark theme', function()
            state.panels.settings:setTheme('dark')
        end, { checked = state.prefs.theme == 'dark' }),
        item('Light theme', function()
            state.panels.settings:setTheme('light')
        end, { checked = state.prefs.theme == 'light' }),
    }
end

Menus.list = {
    { title = 'File', items = file },
    { title = 'Edit', items = edit },
    { title = 'Create', items = create },
    { title = 'View', items = view },
    { title = 'Settings', items = settings },
}

return Menus
