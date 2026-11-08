local ipairs = require('source.engine.math.array').ipairs
local UI = require('source.engine.ui')
local Input = require('source.engine.input.input')
local Version = require('source.engine.core.version')
local Loader = require('source.engine.scenes.loader')
local Catalog = require('source.game.sceneCatalog')
local Tags = require('source.game.sceneTags')

local Menu = {}
Menu.__index = Menu

function Menu.new(manager)
    return setmetatable({ manager = manager, simulation = false }, Menu)
end

function Menu:load()
    self.settings = self.package.settings
    self.resources =
        self.manager.resources:scope(require('source.game.data.manifest'), self.package.paths)
    require('source.engine.ui.sceneRoot').create(self, 1280, 720)
    self.ui.content.name = 'Menu'
    self.input = Input.new(self)
    local panel = self.ui:container({
        position = { 0.5, 0, 0.5, 0 },
        size = { 1, -24, 1, -24 },
        anchorPoint = { 0.5, 0.5 },
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, self.ui.content)
    self.ui:create('UICorner', { radius = { 0, 16 } }, panel)
    self.ui:text({
        position = { 0, 20, 0, 10 },
        size = { 1, -40, 0, 40 },
        text = 'KATSA / 3D + 2D',
        textScaled = true,
        maxTextSize = 30,
        align = 'left',
    }, panel)
    self.ui:text({
        position = { 0, 20, 0, 52 },
        size = { 1, -40, 0, 24 },
        text = 'Katsa ' .. Version.value .. ' • Scenes and interactive labs',
        textScaled = true,
        maxTextSize = 16,
        textColor = { 0.5, 0.75, 0.9 },
        align = 'left',
    }, panel)
    local entries = {}
    for _, entry in ipairs(Catalog.entries) do
        local package = Loader.open(entry.id, Catalog)
        local settings = package.settings
        entries[#entries + 1] = { title = settings.title, id = settings.id, tags = Tags.of(settings) }
        package:release()
    end

    -- Filters: a search box (title, id or tag words) and a tag chooser (a scene needs every
    -- selected tag).
    self.selectedTags = {}
    local searchBox = self.ui:create('TextBox', {
        name = 'SceneSearch',
        position = { 0, 16, 0, 88 },
        size = { 1, -204, 0, 36 },
        placeholderText = 'Search scenes or tags...',
        fontSize = 18,
        padding = 10,
        backgroundColor = { 0.02, 0.04, 0.07 },
        textColor = { 0.85, 0.93, 1 },
        align = 'left',
    }, panel)
    self.searchBox = searchBox
    local tagButton = self.ui:button({
        name = 'SceneTags',
        position = { 1, -180, 0, 88 },
        size = { 0, 164, 0, 36 },
        text = 'Tags ▾',
        textScaled = true,
        maxTextSize = 16,
        radius = 8,
    }, panel)
    self.tagButton = tagButton
    local list = self.ui:scroll({
        name = 'LevelList',
        position = { 0, 16, 0, 136 },
        size = { 1, -32, 1, -178 },
        automaticLength = true,
        contentPadding = 12,
        backgroundColor = { 0.02, 0.04, 0.07 },
    }, panel)
    local ROW = 68

    local function rebuild()
        for i = #list.children, 1, -1 do
            list.children[i]:destroy()
        end
        self.firstSceneButton = nil
        local words = Tags.words(searchBox.text)
        local i = 0
        for _, entry in ipairs(entries) do
            if Tags.matches(entry, self.selectedTags, words) then
                i = i + 1
                local y = (i - 1) * ROW + 4
                local button = self.ui:button({
                    position = { 0, 8, 0, y },
                    size = { 1, -16, 0, ROW - 8 },
                    text = '',
                    backgroundColor = { 0.075, 0.15, 0.23 },
                    radius = 8,
                    onPress = function()
                        self:choose(entry.title, entry.id)
                    end,
                }, list)
                -- Title above, tags below; labels do not take input, the button stays pressable.
                self.ui:text({
                    position = { 0, 14, 0, 5 },
                    size = { 1, -28, 0, 30 },
                    text = entry.title,
                    textScaled = true,
                    maxTextSize = 20,
                    align = 'left',
                }, button)
                self.ui:text({
                    position = { 0, 14, 0, 36 },
                    size = { 1, -28, 0, 20 },
                    text = table.concat(entry.tags, ',  '),
                    fontSize = 14,
                    textColor = { 0.45, 0.72, 0.9 },
                    align = 'left',
                }, button)
                if i == 1 then
                    self.firstSceneButton = button
                end
            end
        end
        list.scrollY = 0
        local count = 0
        for _ in pairs(self.selectedTags) do
            count = count + 1
        end
        tagButton.text = (count > 0 and ('Tags (' .. count .. ')') or 'Tags') .. ' ▾'
        self.ui:invalidate()
    end
    self.rebuildList = rebuild
    rebuild()
    searchBox.onTextChanged = function()
        rebuild()
    end

    local chooser = self.ui:scroll({
        name = 'Tags',
        position = { 1, -280, 0, 128 },
        size = { 0, 264, 0, 320 },
        automaticLength = true,
        contentPadding = 4,
        visible = false,
        zIndex = 100,
        backgroundColor = { 0.025, 0.05, 0.08 },
    }, panel)
    self.tagChooser = chooser
    local all = Tags.collect(entries)
    local chips = {}
    local function refreshChips()
        for tag, chip in pairs(chips) do
            chip.text = (self.selectedTags[tag] and '[x]  ' or '[  ]  ') .. chip.label
            chip.backgroundColor = self.selectedTags[tag] and { 0.12, 0.34, 0.5 } or { 0.075, 0.15, 0.23 }
        end
    end
    self.ui:button({
        position = { 0, 4, 0, 0 },
        size = { 1, -8, 0, 32 },
        text = 'Clear tags',
        fontSize = 16,
        backgroundColor = { 0.35, 0.18, 0.12 },
        onPress = function()
            self.selectedTags = {}
            refreshChips()
            rebuild()
        end,
    }, chooser)
    for i, item in ipairs(all) do
        local chip = self.ui:button({
            position = { 0, 4, 0, i * 36 },
            size = { 1, -8, 0, 32 },
            text = item.tag,
            fontSize = 16,
            align = 'left',
            padding = 10,
            onPress = function()
                if self.selectedTags[item.tag] then
                    self.selectedTags[item.tag] = nil
                else
                    self.selectedTags[item.tag] = true
                end
                refreshChips()
                rebuild()
            end,
        }, chooser)
        chip.label = item.tag .. '  (' .. item.count .. ')'
        chips[item.tag] = chip
    end
    refreshChips()
    -- Replaces the selected tags (a set { tag = true }) and refreshes the chips and the list.
    self.setTags = function(selected)
        self.selectedTags = selected
        refreshChips()
        rebuild()
    end
    tagButton.onPress = function()
        chooser.visible = not chooser.visible
    end

    self.ui:text({
        position = { 0, 20, 1, -34 },
        size = { 1, -40, 0, 24 },
        text = 'Scroll for more scenes • Touch or WASD + drag',
        textScaled = true,
        maxTextSize = 14,
        textColor = { 0.5, 0.65, 0.8 },
    }, panel)
    self.menuPanel = panel
    -- Building a large scene blocks the frame for a while, so the label is drawn first.
    self.loadingLabel = self.ui:text({
        position = { 0.5, 0, 0.5, 0 },
        size = { 1, -40, 0, 48 },
        anchorPoint = { 0.5, 0.5 },
        textScaled = true,
        maxTextSize = 24,
        backgroundColor = { 0.02, 0.05, 0.09 },
        visible = false,
        zIndex = 200,
    }, panel)
    self:resize(katsa.graphics.getDimensions())
end

-- Shows the loading label now and starts the scene on the second frame after this call.
function Menu:choose(title, id)
    if self.pending then
        return
    end
    self.loadingLabel.text = 'Loading ' .. title .. '...'
    self.loadingLabel.visible = true
    self.pending = { id = id, frames = 0 }
    self.ui:invalidate()
end

function Menu:update()
    local pending = self.pending
    if not pending then
        return
    end
    pending.frames = pending.frames + 1
    if pending.frames < 2 then
        return
    end
    self.pending = nil
    local scene, failure
    if pending.id == 'nodeCatalog' then
        scene, failure = self.manager:switch(require('source.game.runtime.nodeCatalog').new)
    else
        scene, failure = self.manager:switch(require('source.game.runtime.application').new, pending.id)
    end
    if not scene and failure then
        -- The scene did not start: stay in the menu and say why instead of showing "Loading..."
        -- forever. The full error is in the error journal and the log.
        local first = tostring(failure):match('[^\n]+') or 'unknown error'
        self.loadingLabel.text = ('Could not load %s: %s'):format(pending.id, first:sub(1, 160))
        self.loadingLabel.visible = true
        self.ui:invalidate()
    end
end

function Menu:draw()
    katsa.graphics.clear(0.025, 0.04, 0.065, 1)
    self.ui:draw()
    self._paintRevision = self.ui.revision
end

function Menu:canReuseWindowFrame()
    -- Observe direct property edits as well as input-driven invalidation before
    -- reusing the presented image. Animated UI must continue rendering normally.
    self.ui:layout()
    return not self.ui.animated and self._paintRevision == self.ui.revision
end

function Menu:resize(w, h)
    self.ui:fit(w, h)
    self.menuPanel.size = { 0, math.min(760, self.ui.width - 24), 1, -24 }
    -- The scroll viewport must fit inside the panel's clipped area after rotation.
    local width = math.min(264, self.ui.width - 56)
    self.tagChooser.size = {
        0,
        width,
        0,
        math.max(1, math.min(320, self.ui.height - 24 - 128 - 42)),
    }
    self.tagChooser.position = { 1, -(width + 16), 0, 128 }
    self.ui:invalidate()
end

function Menu:pointerpressed(id, x, y)
    self.input:press(id, x, y)
end

function Menu:pointermoved(id, x, y, dx, dy)
    self.input:move(id, x, y, dx, dy)
end

function Menu:pointerreleased(id)
    self.input:release(id)
end

function Menu:wheelmoved(x, y)
    self.ui:wheel(katsa.mouse.getX(), katsa.mouse.getY(), y, x)
end

function Menu:keypressed(key)
    if key == 'return' then
        self.manager:switch(require('source.game.runtime.game').new)
    end
end

function Menu:exit()
    self.input:reset()
end

function Menu:release()
    self.world:release()
    self.resources:release()
end

return Menu
