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
    local windows = lab.windows
    self.manager:switch(require('source.game.runtime.menu').new)
    self:check(not windows[1].window:isOpen(), 'Leaving the scene closes its windows')
end

return Module
