local UI = require('source.engine.ui')
local Input = require('source.engine.input.input')
local Bar = require('source.engine.ui.scrolling.scrollBar')
local Text = require('source.engine.ui.drawing.text')
local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED v106.3 ' .. tostring(message))
        os.exit(1)
    end
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    return setmetatable({ manager = manager, count = 0 }, Tests)
end

function Tests:update() end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v106.3', label)
end

function Tests:typography(ui, density)
    local label = ui:text({
        position = { 0, 3.3, 0, 2.7 },
        size = { 0, 320, 0, 60 },
        text = 'Workspace 12345',
        fontSize = 13,
        minTextSize = 13,
        maxTextSize = 13,
        padding = 0,
        align = 'left',
        verticalAlign = 'top',
    }, ui.content)
    local a = katsa.graphics.newCanvas(480 * density, 80 * density, { dpiscale = 1 })
    local b = katsa.graphics.newCanvas(480 * density, 80 * density, { dpiscale = 1 })
    local font = katsa.graphics.newFont(math.floor(13 * density + 0.5), 'normal', 1)
    for _, size in ipairs({ 11, 13, 16, 18, 24 }) do
        label.fontSize, label.minTextSize, label.maxTextSize = size, size, size
        font:release()
        font = katsa.graphics.newFont(math.floor(size * density + 0.5), 'normal', 1)
        for _, mode in ipairs({ 'plain', 'scaled', 'rich' }) do
            label.textScaled, label.richText = mode == 'scaled', mode == 'rich'
            ui:layout()
            katsa.graphics.push('all')
            katsa.graphics.setScissor()
            katsa.graphics.setStencilTest()
            katsa.graphics.setShader()
            katsa.graphics.setColor(1, 1, 1, 1)
            katsa.graphics.origin()
            katsa.graphics.setCanvas(a)
            katsa.graphics.clear(0, 0, 0, 0)
            katsa.graphics.scale(density)
            Text.drawLabel(ui, label)
            katsa.graphics.origin()
            katsa.graphics.setCanvas(b)
            katsa.graphics.clear(0, 0, 0, 0)
            katsa.graphics.setFont(font)
            katsa.graphics.print(
                label.text,
                math.floor(label._x * density + 0.5),
                math.floor(label._y * density + 0.5)
            )
            katsa.graphics.pop()
            local first, second = a:newImageData(), b:newImageData()
            self:check(
                first:getString() == second:getString(),
                'Native-pixel text matches direct rasterization: ' .. mode .. '/' .. density
            )
            if
                size == 13
                and mode == 'plain'
                and density == 1.25
                and os.getenv('KATSA_TEXT_PREVIEW')
            then
                local output = assert(io.open(os.getenv('KATSA_TEXT_PREVIEW'), 'wb'))
                output:write(first:encode('png'):getString())
                output:close()
            end
            first:release()
            second:release()
        end
    end
    label:destroy()
    font:release()
    a:release()
    b:release()
end

function Tests:scrolling(ui, scale)
    local scene = { ui = ui }
    local input = Input.new(scene)
    local frame = ui:scroll({
        position = { 0, 20, 0, 20 },
        size = { 0, 200, 0, 140 },
        scrollingDirection = 'XY',
        canvasSize = { 0, 600, 0, 500 },
        scrollBarThickness = 12,
    }, ui.content)
    local clicks = 0
    local child = ui:button({
        size = { 0, 600, 0, 500 },
        text = 'Content',
        onPress = function()
            clicks = clicks + 1
        end,
    }, frame)
    for _, axis in ipairs({ 'X', 'Y' }) do
        for _, side in ipairs({ 'Left', 'Right' }) do
            frame.verticalScrollBarPosition = side
            ui:layout()
            ui:scrollBy(frame, 100 - frame.scrollY, 100 - frame.scrollX)
            ui:layout()
            local bar = Bar.geometry(frame, axis == 'X')
            local x, y = (bar.x + bar.width * 0.5) * scale, (bar.y + bar.height * 0.5) * scale
            self:check(
                ui:hit(x, y) == frame,
                'Scrollbar wins over overlapping content: ' .. axis .. '/' .. side
            )
            input:press('test', x, y)
            local dx, dy = axis == 'X' and 10 * scale or 0, axis == 'Y' and 10 * scale or 0
            input:move('test', x + dx, y + dy, dx, dy)
            self:check(
                (axis == 'X' and frame.scrollX or frame.scrollY) > 100,
                'Thumb follows positive pointer motion: ' .. axis
            )
            self:check(
                math.abs((axis == 'X' and frame.scrollY or frame.scrollX) - 100) < 0.001,
                'Thumb drag leaves the other axis unchanged'
            )
            input:move('test', x - dx, y - dy, -2 * dx, -2 * dy)
            self:check(
                (axis == 'X' and frame.scrollX or frame.scrollY) < 100,
                'Thumb follows negative pointer motion: ' .. axis
            )
            input:release('test', x - dx, y - dy)
            self:check(
                frame._scrollPointer == nil and frame._scrollAxis == nil,
                'Release clears scrollbar capture'
            )
        end
    end
    for _, direction in ipairs({ 'X', 'Y', 'XY' }) do
        frame.scrollingDirection = direction
        frame.verticalScrollBarPosition = 'Right'
        ui:layout()
        ui:scrollBy(frame, 100 - frame.scrollY, 100 - frame.scrollX)
        ui:layout()
        local x, y = 80 * scale, 80 * scale
        local dx, dy = direction == 'Y' and 0 or 20 * scale, direction == 'X' and 0 or 20 * scale
        input:press('content', x, y)
        input:move('content', x + dx, y + dy, dx, dy)
        input:release('content', x + dx, y + dy)
        self:check(
            (direction == 'Y' or frame.scrollX < 100) and (direction == 'X' or frame.scrollY < 100),
            'Content drag pans naturally: ' .. direction
        )
    end
    for _, direction in ipairs({ 'X', 'Y' }) do
        frame.scrollingDirection = direction
        ui:layout()
        local x, y = 80 * scale, 80 * scale
        local dx, dy = direction == 'Y' and 20 * scale or 0, direction == 'X' and 20 * scale or 0
        input:press('wrong-axis', x, y)
        input:move('wrong-axis', x + dx, y + dy, dx, dy)
        input:release('wrong-axis', x + dx, y + dy)
        self:check(clicks == 0, 'Dragging on a disabled axis does not click content')
    end
    self:check(clicks == 0, 'Dragging bars or content never clicks the covered button')
    frame.scrollingDirection = 'XY'
    ui:layout()
    ui:scrollBy(frame, -frame.scrollY, -frame.scrollX)
    ui:layout()
    local bar = Bar.geometry(frame, false)
    local x, y = (bar.x + 6) * scale, (bar.trackY + bar.trackHeight - 2) * scale
    input:press('track', x, y)
    input:move('track', x, 10000, 0, 10000 - y)
    input:release('track', x, 10000)
    self:check(
        math.abs(frame.scrollY - (frame.absoluteCanvasSize[2] - frame._windowHeight)) < 0.001,
        'Track click and out-of-bounds dragging clamp at the end'
    )
    frame.scrollingDirection = 'XY'
    ui:layout()
    ui:scrollBy(frame, 100 - frame.scrollY, 100 - frame.scrollX)
    ui:layout()
    local board = { canvas = true, drawable = true, onTop = true, ui = ui }
    function board:localPoint(px, py)
        return px / 2, py / 2
    end
    function board:hit(_, _, px, py)
        return ui:hit(px / 2, py / 2)
    end
    local worldScene = {
        ui = {
            hit = function() end,
            blocksWorldClick = function()
                return false
            end,
        },
        world = { activeCamera = {} },
        camera = {},
        renderer = { top = { board }, transparent = {} },
    }
    local worldInput = Input.new(worldScene)
    worldInput:press('world', 160 * scale, 160 * scale)
    worldInput:move('world', 200 * scale, 200 * scale, 40 * scale, 40 * scale)
    worldInput:release('world', 200 * scale, 200 * scale)
    self:check(
        frame.scrollX < 100 and frame.scrollY < 100,
        'World-space scroll content uses the same drag routing in local coordinates'
    )
    frame.scrollBarImageTransparency = 1
    ui:layout()
    self:check(
        frame:scrollBarAt(bar.x + 6, bar.y + 5) == nil,
        'Invisible bars do not intercept input'
    )
    frame.scrollBarImageTransparency = 0
    ui:layout()
    ui:scrollBy(frame, 100 - frame.scrollY, 100 - frame.scrollX)
    local slider =
        ui:slider({ position = { 0, 120, 0, 120 }, size = { 0, 150, 0, 32 }, value = 0.5 }, frame)
    ui:layout()
    local sx, sy = (slider._x + 75) * scale, (slider._y + 16) * scale
    input:press('slider', sx, sy)
    input:move('slider', sx + 20 * scale, sy, 20 * scale, 0)
    input:release('slider', sx + 20 * scale, sy)
    self:check(
        slider.value > 0.5 and frame.scrollX == 100,
        'Horizontal slider gestures retain their own capture'
    )
    input:reset()
    frame:destroy()
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    local scene = self.manager.stack[#self.manager.stack]
    local resources = self.manager.resources:scope()
    local ui = UI.new(480, 320, resources):bindWorld(scene.world)
    for _, scale in ipairs({ 0.75, 1, 1.25, 1.5, 1.75, 2 }) do
        ui.scale = scale
        ui:setDensity(scale)
        self:typography(ui, scale)
        require('source.tests.versions.v106_3.groups').run(self, ui, scale)
        self:scrolling(ui, scale)
        require('source.tests.versions.v106_3.viewport').run(self, ui, scale)
    end
    local joystick = ui:create('VirtualJoystick', { size = { 0, 100, 0, 100 } }, ui.content)
    joystick:setAxes(2, 2)
    self:check(
        joystick:isA('UINode') and math.abs(joystick.axisX ^ 2 + joystick.axisY ^ 2 - 1) < 0.001,
        'Joystick is a reusable UI node with normalized axes'
    )
    joystick:destroy()
    ui:release()
    resources:release()
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' v106.3 checks')
    katsa.event.quit()
end

return Tests
