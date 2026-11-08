-- Several OS windows on one graphics context, and a transparent main window. The main window has no
-- 3D content: its frame is cleared with alpha 0, so only the panel is drawn and the desktop shows
-- through (macOS, Linux with a compositor, Windows through DWM). Three more windows
-- (katsa.window.create) fly around it on Lissajous paths and each draws its own panel.
--   T      toggles the whole main window between opaque and half transparent
--   B      toggles the title bar (borderless)
--   F11    fullscreen (every scene)
--   Space  pauses the flight
--   M      opens / closes a second scene (a mini game) in its own window
--   V      cycles how the windows are moved: budget (default), all every frame, one OS batch
--   Y      switches the main window's per-pixel transparency off and on (same comparison)
--   R      cycles the size of the orbiting windows (windows can be resized at any time)
-- A window closed by its close button is removed; the main window ends the scene as usual.
local Lab = {}
Lab.__index = Lab

local PANELS = {
    { title = 'Orbit A', color = { 0.9, 0.35, 0.3 }, speed = 0.7, radius = { 430, 230 }, phase = 0 },
    { title = 'Orbit B', color = { 0.3, 0.75, 0.45 }, speed = 0.5, radius = { 520, 300 }, phase = 2.1 },
    { title = 'Orbit C', color = { 0.3, 0.55, 0.95 }, speed = 0.9, radius = { 360, 180 }, phase = 4.2 },
}

local WIDTH, HEIGHT = 260, 170
local REDRAW = 12 -- repaints per second of every panel (their motion runs every frame)
local SIZES = { { 260, 170 }, { 340, 220 }, { 180, 120 } }
local MINI_GAME = 'platformer'
-- Moving an OS window costs several milliseconds on Windows (measured: about 6 ms each), so by
-- default only as many windows are moved per frame as fit the budget, the longest waiting first.
local MOVE_BUDGET_MS = 5
local MODES = { 'budget', 'all', 'batch' }

local function drawPanel(panel, time, fps, width, height)
    local g = katsa.graphics
    local color = panel.color
    g.clear(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, 1)
    g.setColor(color[1], color[2], color[3], 1)
    g.rectangle('fill', 0, 0, width, 28)
    g.setColor(1, 1, 1, 1)
    g.print(panel.title, 10, 7)
    -- A ball bouncing inside the panel shows that every window renders on its own.
    local x = width / 2 + math.sin(time * 2 + panel.phase) * (width / 2 - 24)
    local y = 40 + (height - 64) * math.abs(math.sin(time * 1.3 + panel.phase))
    g.circle('fill', x, y, 14)
    g.print(string.format('%d fps', fps), 10, height - 20)
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
        size = { 0, 380, 0, 190 },
        backgroundColor = { 0.08, 0.1, 0.16 },
        backgroundTransparency = 0.2,
    }, ui.content)
    ui:text({
        position = { 0, 14, 0, 10 },
        size = { 1, -28, 1, -20 },
        text = 'Transparent main window\nT  opacity     B  title bar     F11  fullscreen\nM  mini game window     R  resize windows     Space  pause\nV  move mode     Y  transparency',
        fontSize = 17,
        align = 'left',
    }, card)
    self.status = ui:text({
        position = { 0, 14, 1, -34 },
        size = { 1, -28, 0, 24 },
        text = '',
        fontSize = 15,
        textColor = { 0.6, 0.9, 0.7 },
        align = 'left',
    }, card)
    local x, y = katsa.window.getPosition()
    local width, height = katsa.window.getMode()
    self.centerX, self.centerY = x + width / 2, y + height / 2
    for _, panel in ipairs(PANELS) do
        local window = katsa.window.create(WIDTH, HEIGHT, {
            title = panel.title,
            resizable = false,
            -- Owned by the main window (the default): above it, no z-order fights between them.
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
    if self:pressed('v') then
        self.modeIndex = (self.modeIndex or 1) % #MODES + 1
    end
    if self:pressed('y') then
        self.flat = not self.flat
        katsa.window.setTransparent(not self.flat)
    end
    if self.status then
        self.status.text = string.format(
            'moves: %s (%.1f ms per window)   transparency: %s',
            MODES[self.modeIndex or 1],
            self.moveCost or 0,
            self.flat and 'off' or 'on'
        )
    end
    if self:pressed('m') then
        self:toggleMiniGame()
    end
    if self:pressed('r') then
        self.sizeIndex = (self.sizeIndex or 1) % #SIZES + 1
        local size = SIZES[self.sizeIndex]
        for _, entry in ipairs(self.windows) do
            entry.window:setSize(size[1], size[2])
        end
    end
    self:serveWindows(dt)
end

-- Runs while the main window is not focused (the scene's full update is frozen then): the panels
-- keep orbiting, so clicking another application does not stop them.
function Lab:updateInBackground(dt)
    self:serveWindows(dt)
end

-- The motion of the panel windows, shared by update and updateInBackground.
function Lab:serveWindows(dt)
    if not self.paused then
        self.time = self.time + dt
    end
    local count = #self.windows
    if count == 0 then
        return
    end
    local profiler = self.scene.manager and self.scene.manager.profiler
    local clock = katsa.timer.getTime
    -- Moves are limited by a time budget per frame (see MOVE_BUDGET_MS) and the panels' content is
    -- repainted round robin at REDRAW per second: presenting a window costs a context switch and
    -- a swap, which on Windows is several milliseconds.
    local moveStart = clock()
    local mode = MODES[self.modeIndex or 1]
    local due = {}
    for index = #self.windows, 1, -1 do
        local entry = self.windows[index]
        if entry.window:isCloseRequested() then
            entry.window:close()
            table.remove(self.windows, index)
        else
            due[#due + 1] = entry
        end
    end
    self.moveCount = (self.moveCount or 0) + 1
    -- The window that has waited longest goes first; every target is computed from the current
    -- time, so a window served late still lands where it belongs.
    table.sort(due, function(a, b)
        return (a.moved or 0) < (b.moved or 0)
    end)
    local batch = {}
    local moved = 0
    for _, entry in ipairs(due) do
        local width, height = entry.window:getSize()
        local panel = entry.panel
        local angle = self.time * panel.speed + panel.phase
        local x = math.floor(self.centerX + math.cos(angle) * panel.radius[1] - width / 2)
        local y = math.floor(self.centerY + math.sin(angle * 1.3) * panel.radius[2] - height / 2)
        if x ~= entry.x or y ~= entry.y then
            if mode == 'batch' then
                entry.x, entry.y, entry.moved = x, y, self.moveCount
                batch[#batch + 1] = { entry.window, x, y }
            elseif mode == 'all' or moved == 0 or (clock() - moveStart) * 1000 < MOVE_BUDGET_MS then
                local started = clock()
                entry.x, entry.y, entry.moved = x, y, self.moveCount
                entry.window:setPosition(x, y)
                moved = moved + 1
                local cost = (clock() - started) * 1000
                self.moveCost = (self.moveCost or cost) * 0.9 + cost * 0.1
            end
        end
    end
    if #batch > 0 then
        katsa.window.moveWindows(batch)
        self.moveCost = (clock() - moveStart) * 1000 / #batch
    end
    local drawStart = clock()
    count = #self.windows
    self.accumulated = (self.accumulated or 0) + dt
    if count > 0 and self.accumulated >= 1 / (REDRAW * count) then
        self.accumulated = 0
        self.cursor = (self.cursor or 0) % count + 1
        local entry = self.windows[self.cursor]
        local width, height = entry.window:getSize()
        entry.window:draw(function()
            drawPanel(entry.panel, self.time, katsa.timer.getFPS(), width, height)
        end)
    end
    if profiler then
        profiler:sample('Windows: move', (drawStart - moveStart) * 1000)
        profiler:sample('Windows: draw', (clock() - drawStart) * 1000)
    end
end

-- A second scene in its own window: its own world, UI, input and update loop.
function Lab:toggleMiniGame()
    if self.mini and self.mini:isOpen() then
        self.mini:close()
        self.mini = nil
        return
    end
    local window = katsa.window.create(640, 400, { title = 'Mini game', resizable = true })
    if window then
        self.mini = window:runScene(MINI_GAME, { fps = 60 })
    end
end

function Lab:release()
    if self.mini then
        self.mini:close()
    end
    for _, entry in ipairs(self.windows) do
        entry.window:close()
    end
    self.windows = {}
    katsa.window.setOpacity(1)
    katsa.window.setTransparent(false)
    self.scene.clearColor = nil
end

return Lab
