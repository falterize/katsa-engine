-- Mouse moves between two frames resolve the UI hover once, for the newest position.
local Input = require('source.engine.input.input')

local Module = {}

function Module.run(self)
    local hits, last = 0, nil
    local scene = {
        ui = {
            blocksWorldClick = function() return false end,
            offsetX = 0,
            offsetY = 0,
            scale = 1,
            hit = function(_, x, y)
                hits, last = hits + 1, x
            end,
        },
    }
    local input = Input.new(scene, nil)
    for x = 1, 20 do
        input:move('mouse', x, 5, 1, 0)
    end
    self:check(hits == 0, 'mouse moves do not hit-test the UI immediately')
    input:update(1 / 60)
    self:check(hits == 1 and last == 20, 'the frame update hit-tests the newest mouse position once')
    input:update(1 / 60)
    self:check(hits == 1, 'an idle frame does not hit-test again')
    input:move('mouse', 7, 5, 1, 0)
    input:release('mouse', 7, 5)
    input:press('mouse', 7, 5)
    self:check(hits >= 2 and last == 7, 'a press resolves the pending hover first')
    input:reset()
    local before = hits
    input:move('mouse', 9, 5, 1, 0)
    input:reset()
    input:update(1 / 60)
    self:check(hits == before, 'reset drops a pending hover')
end

return Module
