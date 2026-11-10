local Scrolling = {}

function Scrolling.create(ui, parent)
    local frame = ui:scroll({
        name = 'TwoAxisScrollDemo',
        position = { 0, 12, 0, 450 },
        size = { 1, -24, 0, 180 },
        scrollingDirection = 'XY',
        automaticCanvasSize = 'XY',
        contentPadding = 12,
        scrollBarThickness = 6,
        horizontalScrollBarInset = 'ScrollBar',
        verticalScrollBarInset = 'ScrollBar',
        backgroundColor = { 0.025, 0.045, 0.08 },
    }, parent)
    local directions, index = { 'XY', 'X', 'Y' }, 1
    local button = ui:button({
        position = { 0, 12, 0, 398 },
        size = { 1, -24, 0, 42 },
        text = 'Scroll: XY / click to cycle',
        textScaled = true,
        maxTextSize = 18,
    }, parent)
    button:connect('press', function()
        index = index % #directions + 1
        frame.scrollingDirection = directions[index]
        button.text = 'Scroll: ' .. directions[index] .. ' / click to cycle'
    end)
    for row = 1, 4 do
        for column = 1, 6 do
            ui:text({
                name = 'Tile' .. row .. '_' .. column,
                position = { 0, 12 + (column - 1) * 100, 0, 12 + (row - 1) * 72 },
                size = { 0, 88, 0, 60 },
                text = column .. ', ' .. row,
                textScaled = true,
                maxTextSize = 20,
                backgroundColor = { 0.06 + column * 0.025, 0.13 + row * 0.035, 0.32 },
            }, frame)
        end
    end
    return frame
end

return Scrolling
