-- katsa.mouse parity with Love2D: setPosition, grab, visibility and system cursors.
local Module = {}

function Module.run(self)
    local mouse = katsa.mouse
    mouse.setVisible(false)
    local hidden = mouse.isVisible() == false
    mouse.setVisible(true)
    self:check(hidden and mouse.isVisible() == true, 'Mouse visibility is reported, not assumed')
    mouse.setGrabbed(true)
    local grabbed = mouse.isGrabbed()
    mouse.setGrabbed(false)
    self:check(grabbed and not mouse.isGrabbed(), 'The pointer can be confined to the window')
    local cursor = mouse.getSystemCursor('hand')
    mouse.setCursor(cursor)
    self:check(
        cursor ~= nil and mouse.getCursor() == cursor and mouse.getSystemCursor('nonsense') == nil,
        'System cursors are selectable by name'
    )
    mouse.setCursor(nil)
    -- A warp needs pointer focus, which the virtual display of the test host never gives; the
    -- movement itself is verified on a real window.
    self:check(pcall(mouse.setPosition, 120, 80) and pcall(mouse.setX, 10) and pcall(mouse.setY, 10), 'setPosition, setX and setY reach SDL')
end

return Module
