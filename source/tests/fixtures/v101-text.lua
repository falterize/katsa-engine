local ipairs = require('source.engine.math.array').ipairs
local Rich = require('source.engine.ui.drawing.richText')
local Style = require('source.engine.ui.style')
local Text = {}
local utf8 = require('utf8')
local function drawables(node, mode)
    local cache = node._textDrawables
    if not cache then
        cache = {}
        node._textDrawables = cache
        node:onDestroy(function()
            for i = #cache, 1, -1 do
                cache[i]:release()
                cache[i] = nil
            end
        end)
    end
    if cache.mode ~= mode then
        for i = #cache, 1, -1 do
            cache[i]:release()
            cache[i] = nil
        end
        cache.mode = mode
        node._preparedText, node._text = nil, nil
    end
    return cache
end
local function layout(ui, runs, size, width)
    local lines = { { width = 0, height = 0, runs = {} } }
    for _, run in ipairs(runs) do
        local font = ui:font(
            run.size and math.max(1, math.floor(run.size * size / (runs.baseSize or size) + 0.5))
                or size
        )
        for _, code in utf8.codes(run.text) do
            local char = utf8.char(code)
            local line = lines[#lines]
            local cw = font:getWidth(char) + (run.b and 0.6 or 0)
            if char == '\n' or (line.width + cw > width and line.width > 0) then
                lines[#lines + 1] = { width = 0, height = font:getHeight(), runs = {} }
                line = lines[#lines]
            end
            if char ~= '\n' then
                local last = line.runs[#line.runs]
                if last and last.style == run then
                    last.text = last.text .. char
                    last.width = last.width + cw
                else
                    line.runs[#line.runs + 1] =
                        { text = char, font = font, style = run, x = line.width, width = cw }
                end
                line.width = line.width + cw
            end
            line.height = math.max(line.height, font:getHeight() * font:getLineHeight())
        end
    end
    local height, maxWidth = 0, 0
    for _, line in ipairs(lines) do
        line.y = height
        height = height + line.height
        maxWidth = math.max(maxWidth, line.width)
    end
    return lines, height, maxWidth
end
function Text.prepare(ui, node)
    local glyphs = drawables(node, 'rich')
    local padding = node.padding or 6
    local width, height =
        math.max(1, node._width - padding * 2), math.max(1, node._height - padding * 2)
    local base = node.fontSize or 22
    local cache = node._preparedText
    if
        cache
        and cache.text == node.text
        and cache.rich == node.richText
        and cache.scaled == node.textScaled
        and cache.width == width
        and cache.height == height
        and cache.base == base
        and cache.density == ui.density
        and cache.minimum == node.minTextSize
        and cache.maximum == node.maxTextSize
    then
        return node._textLines, node._textHeight
    end
    local runs = Rich.parse(node.text or '', node.richText)
    runs.baseSize = base
    local size = base
    if node.textScaled then
        local low, high = node.minTextSize or 8, node.maxTextSize or 72
        assert(low >= 1 and high >= low and high <= 200, 'Text size limits must be within 1..200')
        size = low
        while low <= high do
            local mid = math.floor((low + high) / 2)
            local _, h, w = layout(ui, runs, mid, width)
            if h <= height and w <= width then
                size = mid
                low = mid + 1
            else
                high = mid - 1
            end
        end
    end
    for i = #glyphs, 1, -1 do
        glyphs[i]:release()
        glyphs[i] = nil
    end
    node._textLines, node._textHeight = layout(ui, runs, size, width)
    for _, line in ipairs(node._textLines) do
        for _, run in ipairs(line.runs) do
            run.drawable = love.graphics.newText(run.font, run.text)
            glyphs[#glyphs + 1] = run.drawable
        end
    end
    cache = cache or {}
    node._preparedText = cache
    cache.text, cache.rich, cache.scaled = node.text, node.richText, node.textScaled
    cache.width, cache.height, cache.base, cache.density = width, height, base, ui.density
    cache.minimum, cache.maximum = node.minTextSize, node.maxTextSize
    node._resolvedTextSize = size
    return node._textLines, node._textHeight
end
function Text.draw(ui, node, dx, dy, outline, exactOffsets)
    local g = love.graphics
    local lines, height = Text.prepare(ui, node)
    local padding = node.padding or 6
    local width = node._width - 2 * padding
    local top = node.verticalAlign == 'top' and node._y + padding
        or node._y + (node._height - height) / 2
    if node.verticalAlign == 'bottom' then
        top = node._y + node._height - padding - height
    end
    local color = Style.color(node, 'text')
    for _, line in ipairs(lines) do
        local x = node._x
            + padding
            + (
                node.align == 'left' and 0
                or node.align == 'right' and width - line.width
                or (width - line.width) / 2
            )
        for _, run in ipairs(line.runs) do
            g.setFont(run.font)
            if not outline then
                local c = run.style.color or color
                g.setColor(c[1], c[2], c[3], Style.alpha(node, 'text', color))
            end
            g.push()
            g.translate(x + run.x + (dx or 0), top + line.y + (dy or 0))
            if run.style.i then
                g.shear(-0.15, 0)
            end
            if exactOffsets then
                g.print(run.text, 0, 0)
                if run.style.b then
                    g.print(run.text, 0.6, 0)
                end
            else
                g.draw(run.drawable, 0, 0)
                if run.style.b then
                    g.draw(run.drawable, 0.6, 0)
                end
            end
            if run.style.u then
                g.line(0, line.height - 2, run.width, line.height - 2)
            end
            if run.style.s then
                g.line(0, line.height * 0.5, run.width, line.height * 0.5)
            end
            g.pop()
        end
    end
end
function Text.drawLabel(ui, node)
    local g = love.graphics
    -- printf rounds fractional outline offsets differently from retained Text.
    -- Keep the original path for outlined labels to preserve their stencil edges.
    local exactOffsets = false
    for _, child in ipairs(node.children) do
        if child:isA('UIStroke') and child.target == 'Text' then
            exactOffsets = true
            break
        end
    end
    -- Retain glyph geometry; rebuild only when wrapping, font, text or alignment changes.
    if not node.textScaled and not node.richText then
        local glyphs = drawables(node, 'fixed')
        local font = ui:font(node.fontSize)
        g.setFont(font)
        local padding = node.padding or 6
        local width = math.max(1, node._width - 2 * padding)
        if
            node._text ~= node.text
            or node._font ~= font
            or node._wrapWidth ~= width
            or node._textAlign ~= node.align
        then
            if glyphs[1] and node._font ~= font then
                glyphs[1]:release()
                glyphs[1] = nil
            end
            glyphs[1] = glyphs[1] or g.newText(font)
            glyphs[1]:setf(node.text, width, node.align or 'center')
            node._textAlign = node.align
            local _, lines = font:getWrap(node.text, width)
            node._textHeight = #lines * font:getHeight() * font:getLineHeight()
            node._text, node._font, node._wrapWidth = node.text, font, width
        end
        local y = node.verticalAlign == 'top' and node._y + padding
            or node._y + (node._height - node._textHeight) / 2
        if node.verticalAlign == 'bottom' then
            y = node._y + node._height - padding - node._textHeight
        end
        local function draw(dx, dy)
            if exactOffsets then
                g.printf(node.text, node._x + padding + dx, y + dy, width, node.align or 'center')
            else
                g.draw(glyphs[1], node._x + padding + dx, y + dy)
            end
        end
        local shader = g.getShader()
        g.push('all')
        g.setShader()
        require('source.engine.ui.drawing.modifiers').textStrokes(node, draw)
        g.setShader(shader)
        require('source.engine.ui.drawing.modifiers').bindGradient(ui, node, 'Text')
        local c = Style.color(node, 'text')
        g.setColor(c[1], c[2], c[3], Style.alpha(node, 'text', c))
        draw(0, 0)
        g.pop()
    else
        local shader = g.getShader()
        g.push('all')
        g.setShader()
        require('source.engine.ui.drawing.modifiers').textStrokes(node, function(dx, dy)
            Text.draw(ui, node, dx, dy, true, exactOffsets)
        end)
        g.setShader(shader)
        require('source.engine.ui.drawing.modifiers').bindGradient(ui, node, 'Text')
        Text.draw(ui, node, nil, nil, false, exactOffsets)
        g.pop()
    end
end
return Text
