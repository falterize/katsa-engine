local Node = require('source.engine.nodes')
local Chart = {}
local Class = Node.define('StatisticsChart', 'Frame')

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    local history = self._history
    if not history or history.count == 0 then
        return
    end
    local seconds = self._seconds or 30
    local summary = history:summary(seconds, self._summary or {}, self._time)
    self._summary = summary
    local low = math.min(0, summary.low)
    local span = math.max(0.001, math.max(0, summary.high) - low)
    local x, y, width, height = self._x + 8, self._y + 8, self._width - 16, self._height - 16
    local cutoff = (self._time or history.lastTime) - seconds
    local g = katsa.graphics
    g.push('all')
    g.setLineWidth(1 / (ui.scale * katsa.graphics.getDPIScale()))
    g.setColor(0.15, 0.22, 0.3, 1)
    for index = 0, 4 do
        local py = y + height * index / 4
        g.line(x, py, x + width, py)
    end
    local step = width * history.interval / seconds
    for index = 1, history.count do
        local bucket = history:get(index)
        if bucket.time >= cutoff then
            local px = x + width * (bucket.time - cutoff) / seconds
            local top = y + height * (1 - (bucket.high - low) / span)
            local bottom = y + height * (1 - (bucket.low - low) / span)
            local mean = y + height * (1 - (bucket.mean - low) / span)
            local zero = y + height * (1 + low / span)
            g.setColor(0.22, 0.82, 0.69, 0.9)
            g.rectangle(
                'fill',
                math.max(x, px - step * 0.8),
                math.min(mean, zero),
                math.max(1, step * 0.65),
                math.max(1, math.abs(mean - zero))
            )
            g.setColor(0.65, 1, 0.88, 1)
            g.line(px, top, px, math.max(top + 1, bottom))
        end
    end
    local average = y + height * (1 - (summary.mean - low) / span)
    g.setColor(1, 0.77, 0.3, 1)
    g.line(x, average, x + width, average)
    g.pop()
end

function Chart.create(ui, parent)
    return ui:create('StatisticsChart', {
        position = { 0, 12, 0, 114 },
        size = { 1, -24, 1, -150 },
        backgroundColor = { 0.025, 0.04, 0.065 },
        backgroundTransparency = 0,
    }, parent)
end

return Chart
