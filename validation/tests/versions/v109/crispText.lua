-- Text is placed on whole physical pixels, so the linear filter does not smear the glyphs.
local Batch = require('source.katsa.graphics.batch')

local Module = {}

function Module.run(self)
    local font = katsa.graphics.newFont(12, 'normal', 2)
    local previous = katsa.graphics.getFont()
    katsa.graphics.setFont(font)
    local original, quads, whole = Batch.addQuad, 0, true
    Batch.addQuad = function(_, x0, y0, x1, y1)
        quads = quads + 1
        -- The quad is local to the print position (10.3, 20.7); two physical pixels per unit.
        local x, y = (x0 + 10.3) * 2, (y0 + 20.7) * 2
        whole = whole and math.abs(x - math.floor(x + 0.5)) < 1e-6
            and math.abs(y - math.floor(y + 0.5)) < 1e-6
    end
    local ok, message = pcall(katsa.graphics.print, 'Crisp text', 10.3, 20.7)
    Batch.addQuad = original
    katsa.graphics.setFont(previous)
    self:check(ok, 'Printing text works: ' .. tostring(message))
    self:check(quads > 0 and whole, 'Glyph quads sit on whole physical pixels')
end

return Module
