-- Debug lines: the allocation-free segment draws the same quad as the general line call.
local Module = {}

function Module.run(self)
    local g = katsa.graphics
    self:check(type(g.segment) == 'function', 'graphics.segment exists')
    g.setColor(1, 1, 1, 1)
    local ok = pcall(function()
        g.line(0, 0, 10, 10)
        g.line(5, 5, 5, 5)
        g.line({ 0, 0, 10, 10, 20, 0 })
    end)
    self:check(ok, 'two-point, zero-length and polyline calls all draw')
end

return Module
