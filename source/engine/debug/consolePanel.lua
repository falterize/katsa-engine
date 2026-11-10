-- On-screen console: level filter (All / Warn / Error), text filter-free tail of katsa.log,
-- JSON/CSV export and Clear. Refreshes only while visible and only when entries arrive.
local Export = require('./logExport')

local Panel = {}
Panel.__index = Panel

local LINES = 200
local ROW = 15 -- pixel height of one 12 px log line
local TAGS = { log = ' ', warn = 'W', error = 'E' }

function Panel.new(ui, parent)
    local self = setmetatable({ ui = ui, filter = nil, dirty = true, visible = false }, Panel)
    self.root = ui:container({
        name = 'Console',
        _viewportAuthored = true,
        position = { 0, 12, 0, 12 },
        size = { 1, -24, 0.45, 0 },
        capture = true,
        visible = false,
        zIndex = 20,
        backgroundColor = { 0.02, 0.03, 0.05 },
        backgroundTransparency = 0.05,
    }, parent)
    local buttons = {
        { 'All', function() self:setFilter(nil) end },
        { 'Warn+', function() self:setFilter('warn') end },
        { 'Errors', function() self:setFilter('error') end },
        { 'JSON', function() self:export('json') end },
        { 'CSV', function() self:export('csv') end },
        { 'Clear', function() katsa.log.clear() end },
    }
    for index, button in ipairs(buttons) do
        do
            local node = ui:button({
                position = { 0, 8 + (index - 1) * 88, 0, 8 },
                size = { 0, 82, 0, 26 },
                text = button[1],
                fontSize = 12,
            }, self.root)
            if button[2] then
                node:connect('press', button[2])
            end
        end
    end
    self.status = ui:text({
        position = { 0, 8 + #buttons * 88, 0, 8 },
        size = { 1, -(16 + #buttons * 88), 0, 26 },
        fontSize = 12,
        align = 'left',
        verticalAlign = 'center',
        _fixedTextLayout = true,
    }, self.root)
    self.scroll = ui:scroll({
        position = { 0, 8, 0, 40 },
        size = { 1, -16, 1, -48 },
        length = 400,
        backgroundColor = { 0.04, 0.05, 0.08 },
    }, self.root)
    self.body = ui:text({
        position = { 0, 6, 0, 4 },
        size = { 1, -12, 0, 380 },
        fontSize = 12,
        align = 'left',
        verticalAlign = 'top',
        _fixedTextLayout = true,
    }, self.scroll)
    self.unsubscribe = katsa.log.subscribe(function()
        self.dirty, self.message = true, nil
    end)
    return self
end

function Panel:setFilter(level)
    self.filter, self.message, self.dirty = level, nil, true
end

function Panel:export(format)
    local ok, result = pcall(function()
        return Export.save(katsa.log.entries(self.filter), format)
    end)
    self.message = ok and ('Saved ' .. result) or ('Export failed: ' .. tostring(result))
    self.dirty = true
end

function Panel:setVisible(visible)
    self.visible = visible
    self.root.visible = visible
    self.dirty = visible
end

function Panel:toggle()
    self:setVisible(not self.visible)
end

function Panel:refresh()
    local entries = katsa.log.entries(self.filter)
    local first = math.max(1, #entries - LINES + 1)
    local lines = {}
    for index = first, #entries do
        local entry = entries[index]
        lines[#lines + 1] = string.format(
            '%s %8.2f  %s',
            TAGS[entry.level],
            entry.time,
            (entry.message:gsub('\n.*', ' ...'))
        )
    end
    self.lines = lines
    local height = math.max(380, #lines * ROW + 12)
    self.scroll.length = height + 8
    self.status.text = self.message
        or string.format(
            '%d entries | %d warnings | %d errors',
            katsa.log.count(),
            katsa.log.count('warn'),
            katsa.log.count('error')
        )
    self:showRows(true)
end

-- Only the rows inside the scroll window (plus a margin) are laid out. The panel keeps up to 200
-- lines, and drawing all of them as one text node cost several milliseconds every frame while
-- the console was open.
function Panel:showRows(force)
    local lines = self.lines
    if not lines then
        return
    end
    local scrollY = self.scroll.scrollY or 0
    local windowHeight = self.scroll._windowHeight or 600
    local first = math.max(1, math.floor(scrollY / ROW) - 1)
    local last = math.min(#lines, first + math.ceil(windowHeight / ROW) + 3)
    if not force and first == self.firstRow and last == self.lastRow then
        return
    end
    self.firstRow, self.lastRow = first, last
    self.body.text = table.concat(lines, '\n', first, last)
    self.body.position = { 0, 6, 0, 4 + (first - 1) * ROW }
    self.body.size = { 1, -12, 0, math.max(0, last - first + 1) * ROW + 12 }
end

function Panel:update()
    if not self.visible then
        return
    end
    if self.dirty then
        self.dirty = false
        self:refresh()
    else
        self:showRows(false)
    end
end

function Panel:release()
    self.unsubscribe()
end

return Panel
