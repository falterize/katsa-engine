-- Text measuring and line layout are memoized per font and give the same results as a fresh font.
local Module = {}

function Module.run(self)
    local cached = katsa.graphics.newFont(14)
    local fresh = katsa.graphics.newFont(14)
    local text = 'The quick brown fox jumps over the lazy dog'
    local first = cached:getWidth(text)
    self:check(cached:getWidth(text) == first and first == fresh:getWidth(text), 'getWidth repeats exactly')
    local widthA, linesA = cached:getWrap(text, 90)
    local widthB, linesB = cached:getWrap(text, 90)
    local widthC, linesC = fresh:getWrap(text, 90)
    self:check(linesA == linesB, 'getWrap returns the memoized result on a repeat')
    self:check(
        widthA == widthC and table.concat(linesA, '|') == table.concat(linesC, '|'),
        'A memoized wrap equals a fresh one'
    )
    local _, narrow = cached:getWrap(text, 60)
    self:check(#narrow > #linesA, 'Another limit is wrapped on its own')
    cached:getWidth('count')
    self:check(cached:getWidth('count') > 0, 'A string named like an internal field stays an entry')
    local quads, count = cached:_lineQuads('Hello')
    local reference = 0
    cached:_layout(require('source.katsa.graphics.font').decode('Hello'), function()
        reference = reference + 1
    end)
    self:check(count == reference and quads == cached:_lineQuads('Hello'), 'Line quads match the layout and are reused')
end

return Module
