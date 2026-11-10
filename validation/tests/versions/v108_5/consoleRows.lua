-- The console lays out only the rows inside its scroll window, not all 200 log lines.
local Panel = require('source.engine.debug.consolePanel')

local Module = {}

local function node(props)
    props.connect = function() end
    return props
end

function Module.run(self)
    local ui = {}
    for _, kind in ipairs({ 'container', 'button', 'text', 'scroll' }) do
        ui[kind] = function(_, props)
            return node(props)
        end
    end
    katsa.log.clear()
    for i = 1, 150 do
        katsa.log.warn('entry ' .. i, 'test', false)
    end
    local panel = Panel.new(ui, nil)
    panel.scroll._windowHeight = 300
    panel.scroll.scrollY = 0
    panel:setVisible(true)
    panel:update()

    local function rows()
        return select(2, panel.body.text:gsub('\n', '\n')) + 1
    end
    self:check(rows() < 30, 'a full log shows only the visible rows (' .. rows() .. ')')
    self:check(panel.body.text:find('entry 150', 1, true) == nil, 'rows below the window are not laid out')
    self:check(panel.scroll.length >= 150 * 15, 'the scroll range still covers every line')

    panel.scroll.scrollY = 1500
    panel:update()
    self:check(panel.body.text:find('entry 100', 1, true) ~= nil, 'scrolling brings later rows into the text')
    self:check(panel.body.position[4] > 1000, 'the text moves down with the window')
    panel:release()
    katsa.log.clear()
end

return Module
