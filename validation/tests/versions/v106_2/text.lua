local Text = require('source.engine.ui.drawing.text')
local Checks = {}

function Checks.run(tests, scene)
    local path = os.getenv('KATSA_REFERENCE_TEXT')
    if not path then
        return
    end
    local file = assert(io.open(path, 'rb'))
    local reference = assert(loadstring(file:read('*a'), 'trusted-text-reference'))()
    file:close()
    local ui = scene.ui
    local label = ui:text({
        size = { 0, 260, 0, 110 },
        textScaled = true,
        minTextSize = 8,
        maxTextSize = 24,
        fontSize = 18,
        align = 'left',
    }, ui.content)
    local a, b = katsa.graphics.newCanvas(320, 160), katsa.graphics.newCanvas(320, 160)
    local contents = {
        '',
        '\n',
        'First\n\nLast\n',
        'Wrapped words and numbers 0123456789 repeated repeated repeated',
        'UTF-8: arrows → and symbols ✓',
        '<b>Bold</b><i>italic</i> <u>underlined</u>\n<font size="27" color="#55CCFF">Large</font>',
    }
    for _, density in ipairs({ 1, 1.25, 2 }) do
        ui:setDensity(density)
        for _, content in ipairs(contents) do
            for _, width in ipairs({ 70, 260 }) do
                label.text, label.richText = content, content:find('<', 1, true) ~= nil
                label.size = { 0, width, 0, 110 }
                ui:layout()
                katsa.graphics.push('all')
                katsa.graphics.origin()
                katsa.graphics.setShader()
                katsa.graphics.setScissor()
                katsa.graphics.setStencilTest()
                katsa.graphics.setCanvas(a)
                katsa.graphics.clear(0, 0, 0, 0)
                label._preparedText = nil
                reference.drawLabel(ui, label)
                local size = label._resolvedTextSize
                katsa.graphics.setCanvas(b)
                katsa.graphics.clear(0, 0, 0, 0)
                label._preparedText = nil
                Text.drawLabel(ui, label)
                katsa.graphics.pop()
                local first, second = a:newImageData(), b:newImageData()
                tests:check(
                    size == label._resolvedTextSize and first:getString() == second:getString(),
                    'Text size, wrapping and pixels match reference at density '
                        .. density
                        .. ', width '
                        .. width
                )
                first:release()
                second:release()
            end
        end
    end
    ui:setDensity(1)
    label.text, label.richText = string.rep('Measurement text 0123 ', 12), false
    label.size = { 0, 260, 0, 110 }
    ui:layout()
    local function allocated(module)
        collectgarbage('collect')
        collectgarbage('stop')
        local before, started = collectgarbage('count'), katsa.timer.getTime()
        for index = 1, 200 do
            label.text = 'Sample ' .. index .. ' ' .. string.rep('Measurement text 0123 ', 12)
            label._preparedText = nil
            module.prepare(ui, label)
        end
        local memory, elapsed = collectgarbage('count') - before, katsa.timer.getTime() - started
        collectgarbage('restart')
        return memory, elapsed * 1000
    end
    local oldMemory, oldTime = allocated(reference)
    local memory, elapsed = allocated(Text)
    print('TEXT PROBE baseline/new KB', oldMemory, memory, 'CPU ms', oldTime, elapsed)
    tests:check(
        memory < oldMemory * 0.8,
        'Measurement-only probes materially reduce text-layout allocation'
    )
    label:destroy()
    a:release()
    b:release()
end

return Checks
