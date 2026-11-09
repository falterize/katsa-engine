-- Every collection scene answers the on-screen joystick and the camera drag area of the common
-- input layer: nothing in a scene's own UI may cover them.
local Tests = {}

function Tests.run(self)
    local Game = require('source.game.runtime.game')
    local Catalog = require('source.game.sceneCatalog')
    local manager = self.manager
    local checked, blocked, hidden = 0, {}, 0
    for _, entry in ipairs(Catalog.entries) do
        if not entry.interface and not entry.standalone and entry.id ~= 'multiplayerCars' then
            local scene = assert(manager:switch(Game.new, entry.id))
            for _ = 1, 3 do
                manager:update(1 / 60)
            end
            manager:draw()
            local layout, ui = scene.input.layout, scene.ui
            local joystick = layout.joystick
            local x = joystick.x * ui.scale + ui.offsetX
            local y = joystick.y * ui.scale + ui.offsetY
            scene:pointerpressed(1, x, y)
            local hit = ui:hit(x, y)
            scene:pointerpressed(1, x, y)
            scene:pointermoved(1, x + joystick.radius * ui.scale * 0.8, y, 0, 0)
            local works = scene.input.joystickId == 1
                and (scene.input.axisX ~= 0 or scene.input.axisY ~= 0)
            scene:pointerreleased(1, x, y)
            if not works and not layout.joystick.blocked then
                blocked[#blocked + 1] = entry.id .. ' (' .. tostring(hit and hit.name) .. ')'
            end
            checked = checked + 1
            hidden = hidden + (layout.joystick.blocked and 1 or 0)
        end
    end
    self:check(#blocked == 0, 'Joystick blocked in: ' .. table.concat(blocked, ', '))
    -- Full-screen tool scenes and scenes without a 3D camera (tileMapLab) hide the joystick.
    self:check(hidden <= 5, 'Only full-screen tool scenes and 2D scenes hide the joystick (' .. hidden .. ')')
    self:check(checked > 20, 'The touch audit covered the collection scenes')
end

return Tests
