local UI = require('source.engine.ui')
return function(test, scene)
    local ui = UI.new(32, 32, scene.resources)
    local a = ui:button({ width = 32, height = 32, color = { 1, 0, 0, 1 }, zIndex = 2 }, ui.content)
    local b = ui:button({ width = 32, height = 32, color = { 0, 1, 0, 1 }, zIndex = 1 }, ui.content)
    test:check(ui:hit(8, 8) == a, 'CanvasGroup zIndex orders drawing and picking consistently')
    a.zIndex = 0
    test:check(ui:hit(8, 8) == b, 'Runtime zIndex edits reorder UI')
    test:check(not pcall(function()
        ui:button({ width = 8, height = 8 })
    end), 'UI creation rejects missing parents')
    test:check(not pcall(function()
        a.parent = ui
    end), 'UI reparenting rejects raw ScreenUI roots')
    ui.content.enabled = false
    test:check(ui:hit(8, 8) == nil, 'Disabled CanvasGroup blocks descendant interaction')
    local disabledCanvas = katsa.graphics.newCanvas(32, 32)
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(disabledCanvas)
    katsa.graphics.clear(0, 0, 0, 1)
    ui:draw()
    katsa.graphics.pop()
    local disabledPixels = disabledCanvas:newImageData()
    test:check(
        select(2, disabledPixels:getPixel(8, 8)) > 0.9,
        'Disabled CanvasGroup stays visible while blocking input'
    )
    ui.content.visible = false
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(disabledCanvas)
    katsa.graphics.clear(0, 0, 0, 1)
    ui:draw()
    katsa.graphics.pop()
    local hiddenPixels = disabledCanvas:newImageData()
    test:check(
        select(2, hiddenPixels:getPixel(8, 8)) == 0,
        'Invisible CanvasGroup hides the entire subtree'
    )
    local presses = 0
    b:connect('press', function()
        presses = presses + 1
    end)
    ui:pointer(b, 'press', 8, 8, 'disabled')
    test:check(presses == 0, 'Disabled or hidden ancestors cancel captured UI input')
    disabledPixels:release()
    hiddenPixels:release()
    disabledCanvas:release()
    ui.content.visible = true
    ui.content.enabled = true
    ui.content.transparency = 1
    test:check(ui:hit(8, 8) == nil, 'Fully transparent CanvasGroup blocks picking')
    ui.content.transparency = 0.5
    a.backgroundColor, b.backgroundColor = { 1, 1, 1 }, { 1, 1, 1 }
    local canvas = katsa.graphics.newCanvas(32, 32)
    katsa.graphics.push('all')
    katsa.graphics.setCanvas(canvas)
    katsa.graphics.clear(0, 0, 0, 1)
    ui:draw()
    katsa.graphics.pop()
    local pixels = canvas:newImageData()
    local red = pixels:getPixel(8, 8)
    test:check(
        red > 0.48 and red < 0.52,
        'CanvasGroup applies opacity once to composited overlapping children'
    )
    pixels:release()
    canvas:release()
    ui:release()
    local board = scene.world.billboards[1]
    test:check(
        board.ui.content == board and board.children[1]:isA('UINode'),
        'BillboardUI directly owns its UI widgets without an extra ScreenUI node'
    )
end
