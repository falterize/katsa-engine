local History = require('source.engine.debug.statistics.history')
local Export = require('source.engine.debug.statistics.export')
local Text = require('source.engine.ui.drawing.text')
local Game = require('source.game.runtime.game')
local Runtime = require('source.engine.core.runtime')

local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED v106.1 ' .. tostring(message))
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
    print('PASS v106.1', label)
end

function Tests:exports()
    local a, b = History.new(), History.new()
    for second = 0, 40 do
        a:sample(second, second)
        b:sample(second, -second)
    end
    local definitions = {
        { id = 'a', label = 'Mean, "quoted"', unit = 'ms' },
        { id = 'b', label = 'Negative\nmetric' },
        { id = 'missing', label = 'Unavailable' },
    }
    local histories = { a = a, b = b }
    local options = {
        scope = 'selected',
        seconds = 5,
        time = 40,
        metricId = 'a',
        scene = 'test',
        backend = 'jolt',
        utc = '2026-10-19T00:00:00Z',
    }
    local csv, rows = Export.build(definitions, histories, options)
    self:check(
        rows == 6 and csv:find('"Mean, ""quoted"""', 1, true),
        'Selected 5s CSV filters history and quotes labels'
    )
    self:check(
        not csv:find('Negative', 1, true) and csv:find(',35,35,1,35,35,35,35', 1, true),
        'Selected export contains only the chosen metric and recorded values'
    )
    options.scope, options.seconds = 'all', 30
    local all, count = Export.build(definitions, histories, options)
    self:check(
        count == 63 and all:find('"Negative\nmetric"', 1, true),
        'All 30s export covers retained metrics with multiline labels'
    )
    self:check(
        all:find(',missing,Unavailable,,,,0,,,,', 1, true),
        'Missing series are explicit, not fabricated numeric samples'
    )
    options.seconds = 7
    self:check(
        not pcall(Export.build, definitions, histories, options),
        'Unsupported export window is rejected'
    )
    options.seconds, options.scope, options.metricId = 5, 'selected', 'invalid'
    self:check(
        not pcall(Export.build, definitions, histories, options),
        'Unknown selected metric is rejected'
    )
    options.scope, options.metricId = 'all', 'a'
    local path1 = Export.save(definitions, histories, options)
    local saved = katsa.filesystem.read(path1)
    local path2 = Export.save(definitions, histories, options)
    self:check(
        path1 ~= path2 and katsa.filesystem.read(path1) == saved,
        'Repeated saves never overwrite an existing export'
    )
    self:check(
        saved:sub(1, 6) == 'schema' and saved:find('\r\n', 1, true),
        'Saved log has a CSV header and CRLF rows'
    )
    local output = os.getenv('KATSA_EXPORT_FIXTURE')
    if output then
        local file = assert(io.open(output, 'wb'))
        file:write(saved)
        file:close()
    end
    assert(katsa.filesystem.remove(path1))
    assert(katsa.filesystem.remove(path2))
end

function Tests:ui()
    local scene =
        assert(self.manager:switch(Game.new, 'animationPhysicsLab', { physicsBackend = 'jolt' }))
    scene.showStats = true
    for _ = 1, 35 do
        self.manager:update(1 / 60)
        self.manager:draw()
    end
    local panel, ui = scene.statistics.panel, scene.ui
    panel:close()
    ui:layout()
    local passes, revision = ui.layoutPasses, ui.revision
    local header = panel.header.text
    panel.header.text = 'Changed fixed-layout diagnostics'
    ui:layout()
    self:check(
        ui.layoutPasses == passes and ui.revision > revision,
        'Fixed diagnostic text invalidates paint without rebuilding geometry'
    )
    panel.header.text = header
    local label = ui:text({
        position = { 0, 20, 0, 20 },
        size = { 0, 300, 0, 100 },
        fontSize = 16,
        textScaled = true,
        minTextSize = 12,
        maxTextSize = 16,
        text = 'Frame 1',
        align = 'left',
    }, ui.content)
    ui:layout()
    passes = ui.layoutPasses
    label.text = 'Frame 2'
    ui:layout()
    self:check(ui.layoutPasses > passes, 'Ordinary text retains its original layout invalidation')
    Text.prepare(ui, label)
    local drawable = label._textDrawables[1]
    label.text = 'Frame 3'
    Text.prepare(ui, label)
    self:check(
        label._textDrawables[1] == drawable,
        'Scaled text changes reuse native glyph buffers'
    )
    label.minTextSize, label.maxTextSize = 13, 13
    Text.prepare(ui, label)
    self:check(
        label._textDrawables[1] == drawable and drawable:getFont() == ui:rasterFont(13),
        'Changing font size updates the retained drawable without replacing it'
    )
    panel:select(3)
    panel:showExport()
    self:check(
        panel.exportDialog.visible and panel.exportButtons[1].enabled,
        'Selected metric enables value-only and all-Stats export choices'
    )
    local paths = {}
    for index, choice in ipairs({
        { 'selected', 5 },
        { 'selected', 30 },
        { 'all', 5 },
        { 'all', 30 },
    }) do
        panel.exportButtons[index].onPress()
        local path = panel.lastExport
        local content = assert(path and katsa.filesystem.read(path))
        self:check(
            content:find(',' .. choice[1] .. ',' .. choice[2] .. ',', 1, true),
            'Export button writes the requested scope/window ' .. index
        )
        paths[#paths + 1] = path
    end
    panel.selected = nil
    panel:showExport()
    self:check(
        not panel.exportButtons[1].enabled and panel.exportButtons[3].enabled,
        'All Stats can be exported without selecting a metric'
    )
    panel:sample(scene.statistics.context, scene.manager.frameTime, false)
    self:check(not panel.exportDialog.visible, 'Closing Stats hides the export dialog')
    for _, path in ipairs(paths) do
        assert(katsa.filesystem.remove(path))
    end
    local reference = os.getenv('KATSA_REFERENCE_TEXT')
    if reference then
        local file = assert(io.open(reference, 'r'))
        local source = file:read('*a')
        file:close()
        local previous = assert(loadstring(source, 'v106-text-reference'))()
        local first, second = katsa.graphics.newCanvas(400, 180), katsa.graphics.newCanvas(400, 180)
        for _, content in ipairs({
            'Wrapped plain text with several words 12345',
            '<b>Bold</b> <i>italic</i> <u>underlined</u>\n<font color="#55CCFF">Color</font>',
        }) do
            label.text, label.richText, label._preparedText =
                content, content:find('<', 1, true) ~= nil, nil
            katsa.graphics.push('all')
            katsa.graphics.setCanvas(first)
            katsa.graphics.clear(0, 0, 0, 0)
            previous.drawLabel(ui, label)
            katsa.graphics.setCanvas(second)
            katsa.graphics.clear(0, 0, 0, 0)
            label._preparedText = nil
            Text.drawLabel(ui, label)
            katsa.graphics.pop()
            local a, b = first:newImageData(), second:newImageData()
            self:check(
                a:getString() == b:getString(),
                'Retained scaled/rich text matches v106 pixels'
            )
            a:release()
            b:release()
        end
        first:release()
        second:release()
    end
    label:destroy()
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    panel:select(3)
    panel:showExport()
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:check(
        Runtime.configured and Runtime.traceBudget >= 8000 and Runtime.machineCodeKiB >= 8192,
        'Startup applies a bounded resident trace/code budget'
    )
    local enabled = jit.status()
    Runtime.initialize()
    self:check(
        jit.status() == enabled,
        'Runtime setup is idempotent and preserves interpreter mode'
    )
    self:exports()
    self:ui()
    print('PASSED ' .. self.count .. ' v106.1 checks')
    local path = os.getenv('KATSA_PREVIEW_PATH')
    if path then
        self.manager:draw()
        katsa.graphics.captureScreenshot(function(image)
            local file = assert(io.open(path, 'wb'))
            file:write(image:encode('png'):getString())
            file:close()
            image:release()
            print('V106.1 PREVIEW COMPLETE')
            katsa.event.quit()
        end)
    else
        katsa.event.quit()
    end
end

return Tests
