-- Esc pause menu as a module a scene attaches in its main.lua:
--
--     require('./pauseMenu').attach(scene)        -- freezes game time while open
--     require('./pauseMenu').attach(scene, true)  -- keeps time running (hosted multiplayer)
--
-- It is an overlay inside the scene, not a scene of its own, so the scene keeps updating under it.
-- Opening sets the time scale to 0 and closing restores the previous value; with `keepTime`
-- the time scale is never touched.
local PauseMenu = {}
PauseMenu.__index = PauseMenu

function PauseMenu.attach(scene, keepTime)
    local menu = setmetatable({ scene = scene, keepTime = keepTime == true }, PauseMenu)
    scene.pauseMenu = menu
    return menu
end

function PauseMenu:isOpen()
    return self.root ~= nil and self.root.visible
end

function PauseMenu:build()
    local scene = self.scene
    local ui = scene.ui
    self.root = ui:container({
        size = { 1, 0, 1, 0 },
        backgroundColor = { 0, 0, 0 },
        backgroundTransparency = 0.4,
        zIndex = 400,
        visible = false,
    }, ui.overlays or ui.content)
    local panel = ui:container({
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 360, 0, 200 },
        anchorPoint = { 0.5, 0.5 },
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, self.root)
    ui:text({
        position = { 0, 16, 0, 12 },
        size = { 1, -32, 0, 40 },
        text = 'Paused',
        fontSize = 26,
        align = 'left',
    }, panel)
    do
        local node = ui:button({
            position = { 0, 12, 0, 62 },
            size = { 1, -24, 0, 48 },
            text = 'Resume',
            fontSize = 19,
            backgroundColor = { 0.1, 0.32, 0.45 },
        }, panel)
        node:connect('press', function()
            self:close()
        end)
    end
    do
        local node = ui:button({
            position = { 0, 12, 0, 122 },
            size = { 1, -24, 0, 48 },
            text = 'Return to menu',
            fontSize = 19,
            backgroundColor = { 0.085, 0.135, 0.19 },
        }, panel)
        node:connect('press', function()
            self.scene.manager:switch(require('source.game.runtime.menu').new)
        end)
    end
end

function PauseMenu:open()
    if self:isOpen() then
        return
    end
    if not self.root then
        self:build()
    end
    self.root.visible = true
    if not self.keepTime then
        local time = self.scene.manager.time
        self.previousScale = time.scale
        time:setScale(0)
    end
    if self.scene.input then
        self.scene.input:reset()
    end
end

function PauseMenu:close()
    if not self:isOpen() then
        return
    end
    self.root.visible = false
    if self.previousScale then
        self.scene.manager.time:setScale(self.previousScale)
        self.previousScale = nil
    end
end

function PauseMenu:toggle()
    if self:isOpen() then
        self:close()
    else
        self:open()
    end
end

-- Scenes forward Esc here; true when the key was handled.
function PauseMenu:keypressed(key)
    if key == 'escape' then
        self:toggle()
        return true
    end
    return false
end

return PauseMenu
