-- The input adapter only updates the reusable UI node; rendering belongs to the UI library.
local View = {}
View.__index = View

function View.new(input)
    local self = setmetatable({ input = input }, View)
    self.node = input.scene.ui:create(
        'VirtualJoystick',
        { name = 'MobileJoystick', position = { 0, 0, 0, 0 }, size = { 0, 0, 0, 0 }, zIndex = -1 },
        input.scene.ui.content
    )
    self:update()
    return self
end

function View:update()
    local j = self.input.layout.joystick
    local n = self.node
    n.position[2], n.position[4] = j.x - j.radius, j.y - j.radius
    n.size[2], n.size[4] = j.radius * 2, j.radius * 2
    n:setAxes(self.input.axisX, self.input.axisY)
end

return View
