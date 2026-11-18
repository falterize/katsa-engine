-- On-screen controls for touch screens, drawn over the viewport: a move stick (forward/back and
-- strafe), a look stick, Up, Down and Fast buttons. They drive the fly camera through
-- FlyCamera:setTouch. Positions are fractions of the viewport and sizes are diameters, both
-- editable: Settings > Touch controls > Edit layout lets you drag every control and resize it
-- (selected control: Smaller / Larger), then the layout is saved with the other preferences.
-- A finger that lands on a control belongs to it (Input:press asks us first); other fingers act as
-- the mouse (input/pointer.lua).
local Kit = require('../support.kit')
local Layout = require('../support.touchLayout')
local Pointer = require('../../input.pointer')

local Panel = {}
Panel.__index = Panel

local MODES = { 'auto', 'on', 'off' }

function Panel.create(state, ui)
    local prefs = state.prefs.touch
    prefs.controls = Layout.merge(prefs.controls)
    local self = setmetatable({
        state = state,
        ui = ui,
        prefs = prefs,
        controls = prefs.controls,
        nodes = {},
        fingers = {},
        axes = { moveStick = { 0, 0 }, lookStick = { 0, 0 } },
        down = {},
        editing = false,
        shownNow = false,
    }, Panel)
    self.root = Kit.make(ui, 'Frame', {
        name = 'TouchControls',
        position = { 0, 0, 0, 0 },
        size = { 0, 0, 0, 0 },
        backgroundTransparency = 1,
        interactable = false,
        zIndex = 30,
        visible = false,
    }, ui.content)
    for _, name in ipairs(Layout.NAMES) do
        if Layout.KIND[name] == 'stick' then
            self.nodes[name] = ui:create('VirtualJoystick', {
                name = 'Touch' .. name,
                size = { 0, 100, 0, 100 },
                knobRadius = 22,
                interactable = false,
            }, self.root)
        else
            self.nodes[name] = Kit.make(ui, 'Button', {
                name = 'Touch' .. name,
                size = { 0, 56, 0, 56 },
                text = Layout.LABEL[name],
                fontSize = 13,
                interactable = false,
            }, self.root, 'tool')
        end
    end
    self.bar = Kit.make(ui, 'Frame', {
        name = 'TouchEditBar',
        size = { 0, 420, 0, 36 },
        zIndex = 31,
        visible = false,
    }, ui.content, 'bar')
    self.hint = Kit.label(ui, self.bar, 'Drag a control to move it', {
        position = { 0, 10, 0, 6 },
        size = { 0, 180, 0, 24 },
    }, 'text')
    local x = 190
    for _, spec in ipairs({
        { 'Smaller', function()
            self:resizeSelected(-10)
        end },
        { 'Larger', function()
            self:resizeSelected(10)
        end },
        { 'Reset', function()
            self.controls = Layout.defaults()
            self.prefs.controls = self.controls
            self.selected = nil
            state:savePrefs()
        end },
        { 'Done', function()
            self:finishEditing()
        end },
    }) do
        local button = Kit.button(ui, self.bar, spec[1], 52, 24, spec[2], 'tool')
        button.position = { 0, x, 0, 6 }
        x = x + 56
    end
    return self
end

local function isMobileOS()
    local ok, os = pcall(katsa.system.getOS)
    return ok and (os == 'Android' or os == 'iOS')
end

function Panel:shown()
    if self.editing then
        return true
    end
    if self.state.playing then
        return false
    end
    local mode = self.prefs.mode
    return mode == 'on' or (mode == 'auto' and (isMobileOS() or Pointer.seen))
end

function Panel:setMode(mode)
    self.prefs.mode = mode
    self.state:savePrefs()
end

function Panel:cycleMode()
    for index, mode in ipairs(MODES) do
        if mode == self.prefs.mode then
            self:setMode(MODES[index % #MODES + 1])
            return
        end
    end
    self:setMode('auto')
end

function Panel:startEditing()
    self.editing, self.selected = true, nil
    self.state.panels.settings:hide()
end

function Panel:finishEditing()
    self.editing = false
    self.state:savePrefs()
end

function Panel:resizeSelected(delta)
    if self.selected then
        Layout.resize(self.controls[self.selected], delta)
        self.state:savePrefs()
    else
        self.state:notify('Touch a control first')
    end
end

-- The viewport rectangle in UI units.
function Panel:view()
    local viewport = self.state.viewport
    local x, y = viewport:getAbsolutePosition()
    local width, height = viewport:getAbsoluteSize()
    return x, y, width, height
end

-- A window pixel position as viewport-local UI units, or nil outside the viewport.
function Panel:local_(px, py)
    local ui = self.ui
    local vx, vy, vw, vh = self:view()
    local x, y = (px - ui.offsetX) / ui.scale - vx, (py - ui.offsetY) / ui.scale - vy
    if x < 0 or y < 0 or x > vw or y > vh then
        return nil
    end
    return x, y, vw, vh
end

-- Input hooks: return true when the finger belongs to a control.
function Panel:press(id, px, py)
    if not self.shownNow then
        return false
    end
    local x, y, width, height = self:local_(px, py)
    if not x then
        return false
    end
    local name = Layout.hit(self.controls, width, height, x, y)
    if not name then
        return false
    end
    local finger = { name = name }
    self.fingers[id] = finger
    if self.editing then
        local cx, cy = Layout.circle(self.controls[name], width, height)
        finger.edit, finger.dx, finger.dy = true, x - cx, y - cy
        self.selected = name
    elseif Layout.KIND[name] == 'stick' then
        self.axes[name] = { Layout.axes(self.controls[name], width, height, x, y) }
    else
        self.down[name] = (self.down[name] or 0) + 1
    end
    return true
end

function Panel:move(id, px, py)
    local finger = self.fingers[id]
    if not finger then
        return false
    end
    local ui = self.ui
    local vx, vy, width, height = self:view()
    local x, y = (px - ui.offsetX) / ui.scale - vx, (py - ui.offsetY) / ui.scale - vy
    if finger.edit then
        Layout.moveTo(self.controls[finger.name], width, height, x - finger.dx, y - finger.dy)
    elseif Layout.KIND[finger.name] == 'stick' then
        self.axes[finger.name] = { Layout.axes(self.controls[finger.name], width, height, x, y) }
    end
    return true
end

function Panel:release(id)
    local finger = self.fingers[id]
    if not finger then
        return false
    end
    self.fingers[id] = nil
    if finger.edit then
        self.state:savePrefs()
    elseif Layout.KIND[finger.name] == 'stick' then
        self.axes[finger.name] = { 0, 0 }
    else
        self.down[finger.name] = math.max(0, (self.down[finger.name] or 1) - 1)
    end
    return true
end

function Panel:reset()
    self.fingers, self.down = {}, {}
    self.axes = { moveStick = { 0, 0 }, lookStick = { 0, 0 } }
end

function Panel:update()
    local state = self.state
    local show = self:shown()
    if show ~= self.shownNow then
        self.shownNow = show
        self.root.visible = show
        if not show then
            self:reset()
            state.fly:setTouch(nil)
        end
    end
    self.bar.visible = self.editing
    if not show then
        return
    end
    local vx, vy, width, height = self:view()
    if width <= 0 or height <= 0 then
        return
    end
    for _, name in ipairs(Layout.NAMES) do
        local node = self.nodes[name]
        local cx, cy, radius = Layout.circle(self.controls[name], width, height)
        node.position = { 0, vx + cx - radius, 0, vy + cy - radius }
        node.size = { 0, radius * 2, 0, radius * 2 }
        if Layout.KIND[name] == 'stick' then
            local a = self.axes[name]
            node.knobRadius = radius * 0.3
            node:setAxes(a[1], a[2])
        else
            local pressed = (self.down[name] or 0) > 0 or (self.editing and self.selected == name)
            if pressed ~= (node.pressedTag == true) then
                node.pressedTag = pressed
                if pressed then
                    node:addTag('on')
                else
                    node:removeTag('on')
                end
                state.styler:apply(node)
            end
        end
    end
    self.bar.position = { 0, vx + math.max(4, (width - 420) / 2), 0, vy + 6 }
    if self.editing then
        local label = self.selected and ('Selected: ' .. Layout.LABEL[self.selected]) or 'Drag a control to move it'
        if self.hint.text ~= label then
            self.hint.text = label
        end
        state.fly:setTouch(nil)
        return
    end
    local move, look = self.axes.moveStick, self.axes.lookStick
    state.fly:setTouch({
        moveX = move[1],
        moveY = move[2],
        vertical = ((self.down.up or 0) > 0 and 1 or 0) - ((self.down.down or 0) > 0 and 1 or 0),
        lookX = look[1],
        lookY = look[2],
        fast = (self.down.fast or 0) > 0,
        lookSpeed = self.prefs.lookSpeed,
    })
end

function Panel:release_()
    for _, node in pairs(self.nodes) do
        if not node.destroyed then
            node:destroy()
        end
    end
    for _, node in ipairs({ self.root, self.bar }) do
        if not node.destroyed then
            node:destroy()
        end
    end
end

return Panel
