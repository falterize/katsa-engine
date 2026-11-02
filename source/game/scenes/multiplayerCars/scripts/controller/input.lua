-- The StareShooter input (scripts/controller/input.lua) for a networked game: the cursor is hidden
-- and captured while playing, the mouse turns the camera at once, Tab (or the on-screen button)
-- gives the cursor back, the wheel zooms, Space/Shift/Ctrl/C/Q drive the character. Added on top:
-- the touch layout (joystick + camera drag, only on phones/tablets), the Run and Crouch toggles
-- for touch, and the typing/menu states of a multiplayer lobby.
local Base = require('source.engine.input.input')

local Input = setmetatable({}, { __index = Base })
Input.__index = Input

local function isTouchDevice()
    local os = katsa.system.getOS()
    return os == 'Android' or os == 'iOS'
end

function Input.new(scene, session)
    local touch = isTouchDevice()
    -- The layout drives the Move/Look actions; on a desktop its joystick and drag regions are
    -- never offered (see press), the mouse and keys do the work.
    local self = setmetatable(Base.new(scene, scene.controls), Input)
    self.session, self.captureWanted, self.touchDevice = session, true, touch
    self.menuKey = 'tab'
    self.runToggled, self.crouchToggled = false, false
    self.actions:bind('Move', { left = 'a', right = 'd', forward = 'w', back = 's' })
    self.actions:on('Look', function(_, look)
        if scene.freeDebugCamera then
            scene.camera:look(look[1], look[2], scene.controls.sensitivity)
        elseif self:playing() then
            session.orbit:look(look[1], look[2])
        end
    end)
    self.actions:on('Jump', function() end) -- The source FSM polls held Space.
    return self
end

-- True while the game owns the mouse and keyboard (no menu, no text field, window focused).
function Input:playing()
    local scene = self.scene
    return self.session.mode == 'playing'
        and scene.manager.focused ~= false
        and self.captureWanted
        and not require('source.engine.ui.widgets.textFocus').current
        and not (scene.workspace and scene.workspace.opened)
        and not scene.showStats
        and not (scene.debugOverlay and scene.debugOverlay.visible)
        and not scene.freeDebugCamera
end

-- Forward/right in -1..1 from the keys and the on-screen joystick; zero while a menu is open.
function Input:axes()
    if not self:playing() then
        return 0, 0
    end
    local keys = self.actions.keys
    local move = self.actions:value('Move')
    local forward = ((keys.up) and 1 or 0) - ((keys.down) and 1 or 0)
    local right = ((keys.right) and 1 or 0) - ((keys.left) and 1 or 0)
    local function strongest(key, stick)
        return math.abs(stick) > math.abs(key) and stick or key
    end
    return strongest(forward, move[3]), strongest(right, move[1])
end

function Input:update(dt)
    local playing = self:playing()
    local relative = playing and not self.touchDevice
    if katsa.mouse.getRelativeMode() ~= relative then
        katsa.mouse.setRelativeMode(relative)
    end
    Base.update(self, dt)
    local walker = self.session.walker
    if walker then
        local input, keys = walker.input, self.actions.keys
        local held = self.session.jumpHeld or 0
        input.jump = playing and (keys.space == true or held > 0)
        input.sprint = playing and (keys.lshift == true or keys.rshift == true or self.runToggled)
        input.crouch = playing and (keys.lctrl == true or keys.c == true or self.crouchToggled)
        input.shiftlock = playing and keys.q == true
        input.forward, input.right = self:axes()
    end
end

function Input:press(id, x, y)
    if id == 'mouse' and katsa.mouse.getRelativeMode() and self:playing() then
        return
    end
    if self.touchDevice then
        return Base.press(self, id, x, y)
    end
    local layout = self.layout
    self.layout = nil
    local ok, problem = pcall(Base.press, self, id, x, y)
    self.layout = layout
    if not ok then
        error(problem, 0)
    end
end

function Input:move(id, x, y, dx, dy)
    if id == 'mouse' and katsa.mouse.getRelativeMode() and self:playing() then
        self.actions:look(dx, dy)
        return
    end
    Base.move(self, id, x, y, dx, dy)
end

-- Tab / the menu button: the cursor comes back (or goes away) and the player menu follows it.
function Input:toggleMenu()
    self.captureWanted = not self.captureWanted
    self:reset()
    local walker = self.session.walker
    if walker then
        local input = walker.input
        input.forward, input.right = 0, 0
        input.jump, input.sprint, input.crouch, input.shiftlock = false, false, false, false
    end
    self.scene:setNavigationVisible(not self.captureWanted)
    self.session:onMenuToggled(not self.captureWanted)
    katsa.mouse.setRelativeMode(self:playing() and not self.touchDevice)
end

function Input:keypressed(key)
    if key == self.menuKey and self.session.mode == 'playing' then
        self:toggleMenu()
        return
    end
    return Base.keypressed(self, key)
end

-- The wheel belongs to the UI under the cursor (scroll frames, any interactable element); the
-- camera zooms only when the game owns the mouse.
function Input:wheelmoved(x, y)
    if not katsa.mouse.getRelativeMode() then
        local ui, mx, my = self.scene.ui, katsa.mouse.getX(), katsa.mouse.getY()
        if ui:wheel(mx, my, y, x) or ui:blocksWorldClick(mx, my, true) then
            return true
        end
    end
    if self:playing() then
        self.session.orbit:zoom(y)
        return true
    end
    return false
end

function Input:draw()
    if self.touchDevice then
        Base.draw(self)
    end
end

return Input
