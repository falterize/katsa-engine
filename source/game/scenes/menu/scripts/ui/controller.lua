local ipairs = require('source.engine.math.array').ipairs
local UI = require('source.engine.ui')
local Input = require('source.engine.input.input')
local Version = require('source.engine.core.version')
local Loader = require('source.engine.scenes.loader')
local Catalog = require('source.game.sceneCatalog')

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
        entries[#entries + 1] = { settings.title, settings.id, settings.category }
        package:release()
    end

    self.category = 'All'
    local categoryButton = self.ui:button({
        name = 'SceneCategory',
        position = { 0, 16, 0, 88 },
        size = { 1, -32, 0, 36 },
        text = 'Category: All ▾',
        textScaled = true,
        maxTextSize = 16,
        radius = 8,
    }, panel)
    self.categoryButton = categoryButton
    local list = self.ui:scroll({
        name = 'LevelList',
        position = { 0, 16, 0, 136 },
        size = { 1, -32, 1, -178 },
        automaticLength = true,
        contentPadding = 12,
        backgroundColor = { 0.02, 0.04, 0.07 },
    }, panel)
    local listed = {}
    for _, entry in ipairs(entries) do
        listed[#listed + 1] = entry
    end

    local function rebuild(category)
        for i = #list.children, 1, -1 do
            list.children[i]:destroy()
        end
        local i = 0
        for _, entry in ipairs(listed) do
            if category == 'All' or (entry[3] or 'UI') == category then
                i = i + 1
                local button = self.ui:button({
                    position = { 0, 8, 0, (i - 1) * 56 + 4 },
                    size = { 1, -16, 0, 48 },
                    text = entry[1],
                    textScaled = true,
                    maxTextSize = 20,
                    align = 'left',
                    padding = 14,
                    backgroundColor = { 0.075, 0.15, 0.23 },
                    radius = 8,
                    onPress = function()
                        self:choose(entry[1], entry[2])
                    end,
                }, list)
                if i == 1 then
                    self.firstSceneButton = button
                end
            end
        end
        list.scrollY = 0
        self.ui:invalidate()
    end
    self.rebuildCategory = rebuild
    rebuild('All')
    local categories, seen = { 'All' }, { All = true }
    for _, entry in ipairs(entries) do
        local category = entry[3] or 'UI'
        if not seen[category] then
            seen[category] = true
            categories[#categories + 1] = category
        end
    end
    local chooser = self.ui:scroll({
        name = 'Categories',
        position = { 0, 16, 0, 128 },
        size = { 0, 260, 0, 280 },
        automaticLength = true,
        contentPadding = 4,
        visible = false,
        zIndex = 100,
        backgroundColor = { 0.025, 0.05, 0.08 },
    }, panel)
    self.categoryChooser = chooser
    for i, category in ipairs(categories) do
        self.ui:button({
            position = { 0, 4, 0, (i - 1) * 36 },
            size = { 1, -8, 0, 32 },
            text = category,
            onPress = function()
                self.category = category
                categoryButton.text = 'Category: ' .. category .. ' ▾'
                chooser.visible = false
                rebuild(category)
            end,
        }, chooser)
    end
    categoryButton.onPress = function()
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
    if pending.id == 'nodeCatalog' then
        self.manager:switch(require('source.game.runtime.nodeCatalog').new)
    else
        self.manager:switch(require('source.game.runtime.application').new, pending.id)
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
    self.categoryChooser.size = {
        0,
        math.min(260, self.ui.width - 56),
        0,
        math.max(1, math.min(280, self.ui.height - 24 - 128 - 42)),
    }
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
