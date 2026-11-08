-- The windowsLab scene opens its windows, moves them and closes them with the scene.
local Module = {}

function Module.run(self)
    local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'windowsLab')
    assert(scene, err)
    local state = scene.instance or scene.state
    scene:update(0.1, 0.1)
    local lab = state and state.windows and state or nil
    if not lab then
        for _, value in pairs(scene) do
            if type(value) == 'table' and value.windows and value.pressed then
                lab = value
            end
        end
    end
    self:check(lab and #lab.windows == 3, 'windowsLab opens its three windows')
    local x1 = lab.windows[1].window:getPosition()
    for _ = 1, 6 do
        scene:update(0.5, 0.5)
    end
    local x2 = lab.windows[1].window:getPosition()
    self:check(x1 ~= x2, 'The windows fly around the main one')
    -- A panel the user drags is left alone instead of being pulled back to its orbit.
    local panel = lab.windows[1]
    lab.windows[1].window:setPosition(321, 222)
    scene:update(0.05, 0.05)
    scene:update(0.05, 0.05)
    local gx, gy = panel.window:getPosition()
    self:check(gx == 321 and gy == 222 and panel.held, 'A panel moved by the user stays where it was put')
    for _ = 1, 12 do
        scene:update(0.1, 0.1)
    end
    self:check(panel.held == nil, 'The orbit goes on after the panel has been let go')
    lab:toggleMiniGame()
    self:check(lab.mini and lab.mini:isOpen(), 'M opens a scene in its own window')
    for _ = 1, 3 do
        scene:update(0.1, 0.1)
    end
    local mini = lab.mini
    local windows = lab.windows
    self.manager:switch(require('source.game.runtime.menu').new)
    self:check(not windows[1].window:isOpen(), 'Leaving the scene closes its windows')
    self:check(not mini:isOpen(), 'Leaving the scene closes the mini game window')
    for _ = 1, 3 do
        katsa.graphics.clear(0, 0, 0, 1)
        katsa.graphics.present()
    end
end

return Module
