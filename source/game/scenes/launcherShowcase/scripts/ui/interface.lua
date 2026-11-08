local ipairs = require('source.engine.math.array').ipairs

-- A launcher window rebuilt from a screenshot: toolbar with icons, grouped instance list,
-- action panel and status bar over a background picture. Everything visual comes from the
-- style sheet (sheet.lua) and the theme tokens of the uiStyler plugin, so the theme button
-- re-skins the whole window at runtime.
local Interface = {}

local ICONS = 'scene://textures/icons/'

local function make(ui, kind, props, parent, ...)
    local node = ui:create(kind, props, parent)
    for _, tag in ipairs({ ... }) do
        node:addTag(tag)
    end
    return node
end

local function toolButton(ui, parent, x, label, icon, onPress)
    local button = make(ui, 'Button', {
        position = { 0, x, 0, 4 },
        size = { 0, 100, 1, -8 },
        text = label,
        verticalAlign = 'bottom',
        onPress = onPress,
    }, parent, 'tool')
    make(ui, 'ImageLabel', {
        position = { 0.5, 0, 0, 4 },
        size = { 0, 30, 0, 30 },
        anchorPoint = { 0.5, 0 },
        image = ICONS .. icon .. '.png',
    }, button, 'icon')
    return button
end

function Interface.create(state)
    local scene = state.scene
    local ui = scene.ui
    -- The style sheet is a node (theme and styles folder in the Inspector); code uses its styler.
    local stylerNode = scene.world:create('UIStyler', {
        name = 'UIStyler',
        theme = 'dark',
        stylesFolder = 'scene://styles',
    })
    local styler = stylerNode:bind(ui, scene.resources)
    state.styler, state.stylerNode = styler, stylerNode

    local root = make(ui, 'Frame', {
        name = 'Launcher',
        position = { 0, 0, 0, 56 },
        size = { 1, 0, 1, -56 },
        _viewportAuthored = true,
    }, ui.content, 'root')
    state.root = root
    make(ui, 'ImageLabel', {
        name = 'Backdrop',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        image = 'scene://textures/background.png',
        imageMode = 'Decal',
        imageTransparency = 0.25,
    }, root)

    -- Toolbar -------------------------------------------------------------------------
    local toolbar = make(ui, 'Frame', {
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 0, 64 },
    }, root, 'toolbar')
    local x = 8
    toolButton(ui, toolbar, x, 'Add Instance', 'add', function() end)
    toolButton(ui, toolbar, x + 108, 'Folders', 'folder', function() end)
    toolButton(ui, toolbar, x + 216, 'Settings', 'gear', function() end)
    toolButton(ui, toolbar, x + 324, 'Help', 'help', function() end)
    toolButton(ui, toolbar, x + 432, 'Update', 'update', function() end)
    local themeButton = toolButton(ui, toolbar, 0, 'Theme: dark', 'gear', nil)
    themeButton.position = { 1, -330, 0, 4 }
    themeButton.onPress = function()
        local next = styler:getTheme() == 'dark' and 'light' or 'dark'
        stylerNode:setTheme(next)
        themeButton.text = 'Theme: ' .. next
    end
    local account = toolButton(ui, toolbar, 0, 'Account', 'account', function() end)
    account.position = { 1, -222, 0, 4 }

    -- Instance list -----------------------------------------------------------------------
    local list = make(ui, 'ScrollFrame', {
        name = 'Instances',
        position = { 0, 12, 0, 76 },
        size = { 1, -252, 1, -76 - 40 },
        automaticLength = true,
        contentPadding = 8,
    }, root, 'listPanel')
    local rows = {}
    local y = 6
    local index = 0
    for _, group in ipairs(state.groups) do
        local header = make(ui, 'Frame', {
            position = { 0, 6, 0, y },
            size = { 1, -12, 0, 28 },
        }, list, 'group')
        make(ui, 'TextLabel', {
            position = { 0, 10, 0, 0 },
            size = { 1, -20, 1, 0 },
            text = group.name,
            align = 'left',
        }, header, 'groupTitle')
        y = y + 34
        for _, instance in ipairs(group.instances) do
            index = index + 1
            local entry = { index = index, instance = instance }
            local row = make(ui, 'Button', {
                position = { 0, 6, 0, y },
                size = { 1, -12, 0, 44 },
                text = '',
            }, list, 'instance')
            make(ui, 'ImageLabel', {
                position = { 0, 8, 0.5, 0 },
                size = { 0, 28, 0, 28 },
                anchorPoint = { 0, 0.5 },
                image = ICONS .. 'cube.png',
            }, row, 'accentIcon')
            make(ui, 'TextLabel', {
                position = { 0, 48, 0, 2 },
                size = { 0.55, -48, 0, 22 },
                text = instance.name,
                align = 'left',
            }, row, 'title')
            make(ui, 'TextLabel', {
                position = { 0, 48, 0, 22 },
                size = { 0.55, -48, 0, 18 },
                text = instance.version,
                align = 'left',
            }, row, 'muted')
            make(ui, 'TextLabel', {
                position = { 0.55, 0, 0, 12 },
                size = { 0.45, -12, 0, 20 },
                text = instance.hours > 0 and (instance.played .. '  -  ' .. instance.hours .. ' h')
                    or instance.played,
                align = 'right',
            }, row, 'muted')
            entry.row = row
            rows[index] = entry
            y = y + 48
        end
        y = y + 6
    end
    list.length = y + 6

    -- Action panel ---------------------------------------------------------------------
    local actions = make(ui, 'Frame', {
        name = 'Actions',
        position = { 1, -228, 0, 76 },
        size = { 0, 216, 1, -76 - 40 },
    }, root, 'actions')
    make(ui, 'ImageLabel', {
        position = { 0.5, 0, 0, 14 },
        size = { 0, 56, 0, 56 },
        anchorPoint = { 0.5, 0 },
        image = ICONS .. 'cube.png',
    }, actions, 'accentIcon')
    local title = make(ui, 'TextLabel', {
        position = { 0, 8, 0, 76 },
        size = { 1, -16, 0, 26 },
        text = '',
        textScaled = true,
        maxTextSize = 18,
    }, actions, 'title')
    local subtitle = make(ui, 'TextLabel', {
        position = { 0, 8, 0, 102 },
        size = { 1, -16, 0, 20 },
        text = '',
    }, actions, 'muted')
    local names = {
        { 'Launch', 'primary' },
        { 'Launch Offline' },
        { 'Kill' , 'danger' },
        { 'Edit' },
        { 'Change Group' },
        { 'Folder' },
        { 'Export' },
        { 'Copy' },
        { 'Delete', 'danger' },
    }
    local top = 134
    for _, spec in ipairs(names) do
        make(ui, 'Button', {
            position = { 0, 12, 0, top },
            size = { 1, -24, 0, 30 },
            text = spec[1],
        }, actions, 'action', spec[2])
        top = top + 36
    end

    -- Status bar ----------------------------------------------------------------------
    local status = make(ui, 'Frame', {
        position = { 0, 0, 1, -28 },
        size = { 1, 0, 0, 28 },
    }, root, 'status')
    make(ui, 'TextLabel', {
        position = { 0, 12, 0, 0 },
        size = { 0.5, 0, 1, 0 },
        text = 'Total playtime: 249 h 14 min',
        align = 'left',
    }, status, 'muted')
    make(ui, 'TextLabel', {
        position = { 0.5, 0, 0, 0 },
        size = { 0.5, -12, 1, 0 },
        text = 'No account selected',
        align = 'right',
    }, status, 'muted')

    local function select(number)
        for _, entry in ipairs(rows) do
            if entry.index == number then
                entry.row:addTag('selected')
            else
                entry.row:removeTag('selected')
            end
        end
        local chosen = rows[number].instance
        title.text = chosen.name
        subtitle.text = chosen.version
        styler:apply(root)
    end
    for _, entry in ipairs(rows) do
        entry.row.onPress = function()
            select(entry.index)
        end
    end
    state.select = select
    styler:setTheme('dark')
    styler:apply(root)
    select(state.selected)
end

return Interface
