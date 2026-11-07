-- Several OS windows on one graphics context, and a transparent main window. The main window has no
-- 3D content: its frame is cleared with alpha 0, so only the panel is drawn and the desktop shows
-- through (macOS, Linux with a compositor, Windows through DWM). Three more windows
-- (katsa.window.create) fly around it on Lissajous paths and each draws its own panel.
--   T      toggles the whole main window between opaque and half transparent
--   B      toggles the title bar (borderless)
--   F11    fullscreen (every scene)
--   Space  pauses the flight
-- A window closed by its close button is removed; the main window ends the scene as usual.
local Lab = {}
Lab.__index = Lab

local PANELS = {
    { title = 'Orbit A', color = { 0.9, 0.35, 0.3 }, speed = 0.7, radius = { 430, 230 }, phase = 0 },
    { title = 'Orbit B', color = { 0.3, 0.75, 0.45 }, speed = 0.5, radius = { 520, 300 }, phase = 2.1 },
    { title = 'Orbit C', color = { 0.3, 0.55, 0.95 }, speed = 0.9, radius = { 360, 180 }, phase = 4.2 },
}

local WIDTH, HEIGHT = 260, 170
local REFRESH = 30 -- panel refreshes per second

local function drawPanel(panel, time, fps)
    local g = katsa.graphics
    local color = panel.color
    g.clear(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, 1)
    g.setColor(color[1], color[2], color[3], 1)
    g.rectangle('fill', 0, 0, WIDTH, 28)
    g.setColor(1, 1, 1, 1)
    g.print(panel.title, 10, 7)
    -- A ball bouncing inside the panel shows that every window renders on its own.
    local x = WIDTH / 2 + math.sin(time * 2 + panel.phase) * (WIDTH / 2 - 24)
    local y = 40 + (HEIGHT - 64) * math.abs(math.sin(time * 1.3 + panel.phase))
    g.circle('fill', x, y, 14)
    g.print(string.format('%d fps', fps), 10, HEIGHT - 20)
end

function Lab.new(scene)
    local self = setmetatable({ scene = scene, time = 0, windows = {}, wasDown = {} }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    scene.clearColor = { 0, 0, 0, 0 }
    katsa.window.setTransparent(true)
    local ui = scene.ui
    local card = ui:container({
        position = { 0.5, -190, 0.5, -70 },
        size = { 0, 380, 0, 140 },
        backgroundColor = { 0.08, 0.1, 0.16 },
        backgroundTransparency = 0.2,
    }, ui.content)
    ui:text({
        position = { 0, 14, 0, 10 },
        size = { 1, -28, 1, -20 },
        text = 'Transparent main window\nT  opacity     B  title bar\nF11  fullscreen     Space  pause',
        fontSize = 17,
        align = 'left',
    }, card)
    local x, y = katsa.window.getPosition()
    local width, height = katsa.window.getMode()
    self.centerX, self.centerY = x + width / 2, y + height / 2
    for _, panel in ipairs(PANELS) do
        local window = katsa.window.create(WIDTH, HEIGHT, {
            title = panel.title,
            resizable = false,
            alwaysontop = true, -- otherwise the main window covers them
        })
        if window then
            self.windows[#self.windows + 1] = { window = window, panel = panel }
        else
            katsa.log.warn('windowsLab: could not open ' .. panel.title)
        end
    end
    return self
end

-- Edge-triggered key press that does not depend on the scene's input actions.
function Lab:pressed(key)
    local down = katsa.keyboard.isDown(key)
    local pressed = down and not self.wasDown[key]
    self.wasDown[key] = down
    return pressed
end

function Lab:update(dt)
    self.scene.world:updateNodes(dt)
    if self:pressed('space') then
        self.paused = not self.paused
    end
    if self:pressed('t') then
        self.opaque = self.opaque == false
        katsa.window.setOpacity(self.opaque and 1 or 0.5)
    end
    if self:pressed('b') then
        katsa.window.setBorderless(not katsa.window.isBorderless())
    end
    if not self.paused then
        self.time = self.time + dt
    end
    -- Moving and presenting an OS window costs a few milliseconds each, so the panels refresh at
    -- 30 Hz instead of every frame of the main window.
    self.accumulated = (self.accumulated or 0) + dt
    if self.accumulated < 1 / REFRESH then
        return
    end
    self.accumulated = 0
    local fps = katsa.timer.getFPS()
    for index = #self.windows, 1, -1 do
        local entry = self.windows[index]
        local window, panel = entry.window, entry.panel
        if window:isCloseRequested() then
            window:close()
            table.remove(self.windows, index)
        else
            local angle = self.time * panel.speed + panel.phase
            window:setPosition(
                math.floor(self.centerX + math.cos(angle) * panel.radius[1] - WIDTH / 2),
                math.floor(self.centerY + math.sin(angle * 1.3) * panel.radius[2] - HEIGHT / 2)
            )
            window:draw(function()
                drawPanel(panel, self.time, fps)
            end)
        end
    end
end

function Lab:release()
    for _, entry in ipairs(self.windows) do
        entry.window:close()
    end
    self.windows = {}
    katsa.window.setOpacity(1)
    katsa.window.setTransparent(false)
    self.scene.clearColor = nil
end

return Lab
