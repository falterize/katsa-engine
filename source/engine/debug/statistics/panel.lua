local History = require('./history')
local Chart = require('./chart')
local Export = require('./export')

local Panel = {}
Panel.__index = Panel

local function text(ui, parent, y, height, size)
    return ui:text({
        position = { 0, 12, 0, y },
        size = { 1, -24, 0, height },
        fontSize = size or 13,
        align = 'left',
        verticalAlign = 'top',
        _fixedTextLayout = true,
    }, parent)
end

function Panel.new(ui, parent, definitions)
    local self = setmetatable({
        ui = ui,
        definitions = definitions,
        histories = {},
        backgroundDefinitions = {},
        rows = {},
        nextRefresh = 0,
        seconds = 30,
    }, Panel)
    for _, definition in ipairs(definitions) do
        if definition.background then
            self.backgroundDefinitions[#self.backgroundDefinitions + 1] = definition
            self.histories[definition.id] = History.new(nil, nil, definition.aggregation)
        end
    end
    self.scroll = ui:scroll({
        name = 'Statistics',
        _viewportAuthored = true,
        position = { 0.5, 0, 1, -12 },
        size = { 0, 560, 0, 180 },
        anchorPoint = { 0.5, 1 },
        length = 126 + #definitions * 30,
        backgroundColor = { 0.025, 0.045, 0.075 },
    }, parent)
    self.header = text(ui, self.scroll, 8, 76)
    self.header.textScaled, self.header.minTextSize, self.header.maxTextSize = true, 10, 13
    ui:button({
        position = { 0, 8, 0, 84 },
        size = { 1, -16, 0, 30 },
        text = 'Export Stats logs...',
        fontSize = 13,
        onPress = function()
            self:showExport()
        end,
    }, self.scroll)
    self.popup = ui:container({
        name = 'StatisticsHistory',
        _viewportAuthored = true,
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 680, 0, 350 },
        anchorPoint = { 0.5, 0.5 },
        capture = true,
        visible = false,
        zIndex = 10,
        backgroundColor = { 0.035, 0.06, 0.095 },
        backgroundTransparency = 0,
    }, parent)
    self.title = text(ui, self.popup, 12, 24, 17)
    self.title.size = { 1, -60, 0, 24 }
    self.title.textScaled, self.title.minTextSize, self.title.maxTextSize = true, 10, 17
    self.summary = text(ui, self.popup, 44, 60)
    self.summary.textScaled, self.summary.minTextSize, self.summary.maxTextSize = true, 10, 13
    self.chart = Chart.create(ui, self.popup)
    self.chart.size = { 1, -24, 1, -182 }
    self.legend = text(ui, self.popup, 320, 24, 12)
    self.legend.text = 'Bars: mean | whiskers: min/max | yellow line: window mean'
    ui:button({
        position = { 0, 12, 1, -34 },
        size = { 0, 132, 0, 28 },
        text = 'Export logs...',
        fontSize = 12,
        onPress = function()
            self:showExport()
        end,
    }, self.popup)
    ui:button({
        position = { 1, -44, 0, 8 },
        size = { 0, 32, 0, 28 },
        text = 'X',
        onPress = function()
            self:close()
        end,
    }, self.popup)
    for index, seconds in ipairs({ 5, 30 }) do
        ui:button({
            position = { 1, -184 + (index - 1) * 82, 1, -34 },
            size = { 0, 76, 0, 28 },
            text = 'Last ' .. seconds .. 's',
            fontSize = 12,
            onPress = function()
                self.seconds = seconds
                self:refreshChart()
            end,
        }, self.popup)
    end
    self:buildExport(parent)
    return self
end

function Panel:buildExport(parent)
    self.exportBlocker = self.ui:container({
        size = { 1, 0, 1, 0 },
        _viewportAuthored = true,
        capture = true,
        visible = false,
        zIndex = 19,
    }, parent)
    self.exportDialog = self.ui:container({
        name = 'StatisticsExport',
        _viewportAuthored = true,
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 470, 0, 300 },
        anchorPoint = { 0.5, 0.5 },
        visible = false,
        capture = true,
        zIndex = 20,
        backgroundColor = { 0.035, 0.06, 0.095 },
        backgroundTransparency = 0,
    }, parent)
    text(self.ui, self.exportDialog, 12, 26, 17).text = 'Export recorded Stats'
    self.exportButtons = {}
    for index, choice in ipairs({
        { 'selected', 5 },
        { 'selected', 30 },
        { 'all', 5 },
        { 'all', 30 },
    }) do
        local scope, seconds = choice[1], choice[2]
        self.exportButtons[index] = self.ui:button({
            position = { 0, 12, 0, 44 + (index - 1) * 36 },
            size = { 1, -24, 0, 32 },
            text = (scope == 'selected' and 'Selected value' or 'All Stats')
                .. ' / last '
                .. seconds
                .. 's',
            fontSize = 13,
            textScaled = true,
            maxTextSize = 13,
            onPress = function()
                self:export(scope, seconds)
            end,
        }, self.exportDialog)
    end
    self.exportStatus = text(self.ui, self.exportDialog, 192, 58, 12)
    self.exportStatus.textScaled, self.exportStatus.maxTextSize = true, 12
    self.ui:button({
        position = { 0, 12, 1, -40 },
        size = { 0.55, -18, 0, 30 },
        text = 'Open log folder',
        fontSize = 13,
        onPress = function()
            katsa.filesystem.createDirectory('stats-logs')
            local path = (katsa.filesystem.getSaveDirectory() .. '/stats-logs'):gsub('\\', '/')
            katsa.system.openURL(
                ('file://' .. (path:sub(1, 1) == '/' and '' or '/') .. path):gsub(' ', '%%20')
            )
        end,
    }, self.exportDialog)
    self.ui:button({
        position = { 0.55, 0, 1, -40 },
        size = { 0.45, -12, 0, 30 },
        text = 'Close',
        onPress = function()
            self.exportDialog.visible = false
            self.exportBlocker.visible = false
        end,
    }, self.exportDialog)
end

function Panel:showExport()
    self.exportDialog.visible = true
    self.exportBlocker.visible = true
    self.exportButtons[1].enabled, self.exportButtons[2].enabled =
        self.selected ~= nil, self.selected ~= nil
    local definition = self.selected and self.definitions[self.selected]
    self.exportStatus.text = definition and 'Selected: ' .. definition.label
        or 'Select a metric for value-only export. All Stats is available.'
end

function Panel:export(scope, seconds)
    local metadata = self.exportMetadata or {}
    local options = {
        scope = scope,
        seconds = seconds,
        time = self.latestTime or 0,
        metricId = self.selected and self.definitions[self.selected].id,
        scene = metadata.scene,
        backend = metadata.backend,
    }
    local ok, path, rows = pcall(Export.save, self.definitions, self.histories, options)
    self.exportStatus.text = ok
            and ('Saved ' .. rows .. ' CSV rows. Open log folder to view the file.')
        or ('Export failed: ' .. tostring(path))
    if ok then
        self.lastExport = path
    end
    return ok, path
end

function Panel:ensureRows()
    if #self.rows > 0 then
        return
    end
    -- UI rows and detailed histories remain lazy; background frame histories
    -- must survive opening the panel so hidden-overlay stalls remain visible.
    for index, definition in ipairs(self.definitions) do
        self.histories[definition.id] = self.histories[definition.id]
            or History.new(nil, nil, definition.aggregation)
        self.rows[index] = self.ui:button({
            position = { 0, 8, 0, 124 + (index - 1) * 30 },
            size = { 1, -16, 0, 28 },
            text = definition.label .. ': --',
            _fixedTextLayout = true,
            clip = true,
            fontSize = 13,
            textScaled = true,
            minTextSize = 10,
            maxTextSize = 13,
            align = 'left',
            backgroundTransparency = 0.6,
            onPress = function()
                self:select(index)
            end,
        }, self.scroll)
    end
end

function Panel:resize()
    local width, height = self.ui.width, self.ui.height
    self.scroll.size = {
        0,
        math.max(1, math.min(560, width - 24)),
        0,
        math.max(1, math.min(180, height - 110)),
    }
    self.popup.size = {
        0,
        math.max(1, math.min(680, width - 24)),
        0,
        math.max(200, math.min(350, height - 24)),
    }
    self.legend.position = { 0, 12, 1, -64 }
    self.legend.textScaled, self.legend.maxTextSize = true, 12
    self.exportDialog.size = {
        0,
        math.max(1, math.min(470, width - 24)),
        0,
        math.max(220, math.min(300, height - 24)),
    }
    local compact = self.exportDialog.size[4] < 280
    for index, button in ipairs(self.exportButtons) do
        button.position =
            { 0, 12, 0, (compact and 38 or 44) + (index - 1) * (compact and 28 or 36) }
        button.size = { 1, -24, 0, compact and 26 or 32 }
    end
    self.exportStatus.position = { 0, 12, 0, compact and 150 or 192 }
    self.exportStatus.size = { 1, -24, 0, compact and 28 or 58 }
end

function Panel:select(index)
    assert(self.definitions[index], 'Unknown statistics row')
    self:ensureRows()
    self.selected = index
    self.popup.visible = true
    self:refreshChart()
end

function Panel:close()
    self.popup.visible = false
end

function Panel:refreshChart()
    if not self.selected then
        return
    end
    local definition = self.definitions[self.selected]
    local history = self.histories[definition.id]
    local full = history:summary(30, self._full or {}, self.latestTime)
    local recent = history:summary(5, self._recent or {}, self.latestTime)
    local window = history:summary(self.seconds, self._window or {}, self.latestTime)
    self._window = window
    self._full, self._recent = full, recent
    self.title.text = definition.label .. ' (' .. (definition.unit or 'count') .. ')'
    self.summary.text = string.format(
        'Now %s | mean (30s) %.2f | mean (5s) %.2f\nPlot %ds | min %.2f | max %.2f',
        definition.last ~= nil and string.format('%.3f', definition.last) or 'unavailable',
        full.mean,
        recent.mean,
        self.seconds,
        window.low,
        window.high
    )
    if full.count == 0 then
        self.summary.text =
            'No recorded samples for this metric.\nValues appear when the subsystem reports them.'
    end
    self.chart._history, self.chart._seconds = history, self.seconds
    self.ui:invalidatePaint()
end

-- Readers return nil for unavailable metrics, preserving gaps instead of inventing zeroes.
function Panel:sample(context, time, visible)
    self.latestTime = time
    self.chart._time = time
    self.scroll.visible = visible
    if visible then
        self:ensureRows()
    end
    local definitions = visible and self.definitions or self.backgroundDefinitions
    for _, definition in ipairs(definitions) do
        local value = definition.read(context)
        definition.last = value
        if value ~= nil then
            self.histories[definition.id]:sample(time, value)
        end
    end
    if not visible then
        self:close()
        self.exportDialog.visible = false
        self.exportBlocker.visible = false
        return
    end
    if time < self.nextRefresh then
        return
    end
    self.nextRefresh = time + 0.25
    for index, definition in ipairs(self.definitions) do
        local row = self.rows[index]
        -- Offscreen labels do not need formatting or new text layouts. Histories still sample all
        -- rows.
        if
            row._y
            and row._height
            and row._y + row._height >= self.scroll._y
            and row._y <= self.scroll._y + self.scroll._height
        then
            row.text = definition.label
                .. ': '
                .. (definition.last and string.format('%.2f', definition.last) or '--')
                .. ' '
                .. (definition.unit or '')
                .. '  >'
        end
    end
    if self.popup.visible then
        self:refreshChart()
    end
end

return Panel
