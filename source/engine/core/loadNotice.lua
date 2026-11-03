-- The "Loading ..." card drawn over the current scene while the next one is being built.
local LoadNotice = {}

function LoadNotice.draw(label)
    local g = katsa.graphics
    local width, height = g.getDimensions()
    g.push('all')
    g.setColor(0, 0, 0, 0.55)
    g.rectangle('fill', 0, 0, width, height)
    g.setColor(1, 1, 1, 1)
    g.printf(label, 0, height / 2 - 8, width, 'center')
    g.pop()
end

return LoadNotice
