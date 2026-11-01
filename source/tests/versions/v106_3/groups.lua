local Groups = {}

function Groups.run(tests, ui, density)
    local group = ui:canvasGroup({
        position = { 0, 3.3, 0, 2.7 },
        size = { 0, 320, 0, 60 },
        transparency = 0.5,
    })
    ui:text({
        size = { 1, 0, 1, 0 },
        text = 'Workspace 12345',
        fontSize = 13,
        padding = 0,
        align = 'left',
        verticalAlign = 'top',
    }, group)
    local a = katsa.graphics.newCanvas(480 * density, 80 * density, { dpiscale = 1 })
    local b = katsa.graphics.newCanvas(480 * density, 80 * density, { dpiscale = 1 })
    local font = katsa.graphics.newFont(math.floor(13 * density + 0.5), 'normal', 1)
    katsa.graphics.push('all')
    katsa.graphics.setCanvas({ a, stencil = true })
    katsa.graphics.origin()
    katsa.graphics.setScissor()
    katsa.graphics.setStencilTest()
    katsa.graphics.setShader()
    katsa.graphics.clear(0, 0, 0, 0, 0)
    ui:draw()
    local cached = group._groupCanvas
    katsa.graphics.clear(0, 0, 0, 0, 0)
    ui:draw()
    katsa.graphics.setCanvas(b)
    katsa.graphics.origin()
    katsa.graphics.clear(0, 0, 0, 0)
    katsa.graphics.setColor(1, 1, 1, 0.5)
    katsa.graphics.setFont(font)
    katsa.graphics.print(
        'Workspace 12345',
        math.floor(3.3 * density + 0.5),
        math.floor(2.7 * density + 0.5)
    )
    katsa.graphics.pop()
    tests:check(
        group._groupCanvas == cached and cached:getDPIScale() == 1,
        'CanvasGroup reuses a physical-pixel target at density ' .. density
    )
    local first, second = a:newImageData(), b:newImageData()
    local maximum = 0
    for y = 0, first:getHeight() - 1 do
        for x = 0, first:getWidth() - 1 do
            local r, g, blue, alpha = first:getPixel(x, y)
            local rr, gg, bb, aa = second:getPixel(x, y)
            maximum = math.max(
                maximum,
                math.abs(r - rr),
                math.abs(g - gg),
                math.abs(blue - bb),
                math.abs(alpha - aa)
            )
        end
    end
    print('GROUP PIXEL ERROR', density, maximum)
    tests:check(
        maximum <= 2 / 255,
        'CanvasGroup compositing preserves glyph pixels within alpha rounding'
    )
    first:release()
    second:release()
    a:release()
    b:release()
    font:release()
    group:destroy()
end

return Groups
