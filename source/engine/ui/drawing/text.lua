local ipairs = require('../../math.array').ipairs
local Rich = require('./richText')
local Style = require('../style')
local utf8 = require('utf8')
local pixelOrigin = require('./pixelGrid').snap

local Text = {}

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

local function layout(ui, runs, size, width, measureOnly, heightLimit)
    local lines = not measureOnly and { { width = 0, height = 0, runs = {} } }
    local lineWidth, lineHeight, height, maxWidth = 0, 0, 0, 0
    for _, run in ipairs(runs) do
        local font, rasterScale = ui:rasterFont(
            run.size and math.max(1, math.floor(run.size * size / (runs.baseSize or size) + 0.5))
                or size,
            runs.fontPath
        )
        local fontHeight = font:getHeight() * rasterScale
        local spacing = fontHeight * font:getLineHeight()
        for _, code in utf8.codes(run.text) do
            local char = utf8.char(code)
            local cw = font:getWidth(char) * rasterScale + (run.b and 0.6 or 0)
            if char == '\n' or (lineWidth + cw > width and lineWidth > 0) then
                height = height + lineHeight
                maxWidth = math.max(maxWidth, lineWidth)
                lineWidth, lineHeight = 0, fontHeight
                if measureOnly and height + lineHeight > heightLimit then
                    return nil, math.huge, math.huge
                end
                if lines then
                    lines[#lines + 1] = { width = 0, height = fontHeight, runs = {} }
                end
            end
            if char ~= '\n' then
                if lines then
                    local line = lines[#lines]
                    local last = line.runs[#line.runs]
                    if last and last.style == run then
                        last.text = last.text .. char
                        last.width = last.width + cw
                    else
                        line.runs[#line.runs + 1] = {
                            text = char,
                            font = font,
                            rasterScale = rasterScale,
                            style = run,
                            x = lineWidth,
                            width = cw,
                        }
                    end
                end
                lineWidth = lineWidth + cw
            end
            lineHeight = math.max(lineHeight, spacing)
            if lines then
                local line = lines[#lines]
                line.width, line.height = lineWidth, lineHeight
            end
        end
    end
    height = height + lineHeight
    maxWidth = math.max(maxWidth, lineWidth)
    if lines then
        local y = 0
        for _, line in ipairs(lines) do
            line.y = y
            y = y + line.height
        end
    end
    return lines, height, maxWidth
end

local function drawPlain(node, font, glyphs, y, width, exactOffsets, dx, dy)
    local g = katsa.graphics
    local rasterScale = node._rasterScale
    if exactOffsets then
        local textX, textY = pixelOrigin(g, node._x + (node.padding or 6), y)
        g.printf(
            node.text,
            textX + dx,
            textY + dy,
            width / rasterScale,
            node.align or 'center',
            0,
            rasterScale,
            rasterScale
        )
    else
        local lineHeight = font:getHeight() * font:getLineHeight() * rasterScale
        for i, glyph in ipairs(glyphs) do
            local lineWidth = glyph:getWidth() * rasterScale
            local offset = node.align == 'left' and 0
                or node.align == 'right' and width - lineWidth
                or (width - lineWidth) / 2
            -- Snap the actual aligned line, not just the outer label rectangle.
            local x, y =
                pixelOrigin(g, node._x + (node.padding or 6) + offset, y + (i - 1) * lineHeight)
            g.draw(glyph, x + dx, y + dy, 0, rasterScale, rasterScale)
        end
    end
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
        and cache.font == node.font
    then
        return node._textLines, node._textHeight
    end
    local runs = Rich.parse(node.text or '', node.richText)
    runs.baseSize = base
    runs.fontPath = node.font
    local size = base
    -- Font-size probes need only measurements, not temporary lines, runs or concatenated strings.
    if node.textScaled then
        local low, high = node.minTextSize or 8, node.maxTextSize or 72
        assert(low >= 1 and high >= low and high <= 200, 'Text size limits must be within 1..200')
        size = low
        local _, maximumHeight, maximumWidth = layout(ui, runs, high, width, true, height)
        if maximumHeight <= height and maximumWidth <= width then
            size, low = high, high + 1
        else
            high = high - 1
        end
        while low <= high do
            local mid = math.floor((low + high) / 2)
            local _, h, w = layout(ui, runs, mid, width, true, height)
            if h <= height and w <= width then
                size = mid
                low = mid + 1
            else
                high = mid - 1
            end
        end
    end
    node._textLines, node._textHeight = layout(ui, runs, size, width)
    local count = 0
    for _, line in ipairs(node._textLines) do
        for _, run in ipairs(line.runs) do
            count = count + 1
            local drawable = glyphs[count]
            if drawable then
                if drawable:getFont() ~= run.font then
                    drawable:setFont(run.font)
                end
                drawable:set(run.text)
            else
                drawable = katsa.graphics.newText(run.font, run.text)
                glyphs[count] = drawable
            end
            run.drawable = drawable
        end
    end
    -- Keep native Text buffers across content/scale changes, but release unused runs.
    for i = #glyphs, count + 1, -1 do
        glyphs[i]:release()
        glyphs[i] = nil
    end
    cache = cache or {}
    node._preparedText = cache
    cache.text, cache.rich, cache.scaled = node.text, node.richText, node.textScaled
    cache.width, cache.height, cache.base, cache.density = width, height, base, ui.density
    cache.minimum, cache.maximum = node.minTextSize, node.maxTextSize
    cache.font = node.font
    node._resolvedTextSize = size
    return node._textLines, node._textHeight
end

function Text.draw(ui, node, dx, dy, outline, exactOffsets)
    local g = katsa.graphics
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
            local tx, ty = pixelOrigin(g, x + run.x, top + line.y)
            g.translate(tx + (dx or 0), ty + (dy or 0))
            if run.style.i then
                g.shear(-0.15, 0)
            end
            if exactOffsets then
                g.print(run.text, 0, 0, 0, run.rasterScale, run.rasterScale)
                if run.style.b then
                    g.print(run.text, 0.6, 0, 0, run.rasterScale, run.rasterScale)
                end
            else
                g.draw(run.drawable, 0, 0, 0, run.rasterScale, run.rasterScale)
                if run.style.b then
                    g.draw(run.drawable, 0.6, 0, 0, run.rasterScale, run.rasterScale)
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
    local g = katsa.graphics
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
        local font, rasterScale = ui:rasterFont(node.fontSize, node.font)
        g.setFont(font)
        local scaleChanged = node._rasterScale ~= rasterScale
        node._rasterScale = rasterScale
        local padding = node.padding or 6
        local width = math.max(1, node._width - 2 * padding)
        if
            node._text ~= node.text
            or scaleChanged
            or node._font ~= font
            or node._wrapWidth ~= width
            or node._textAlign ~= node.align
        then
            local _, lines = font:getWrap(node.text, width / rasterScale)
            for i = #glyphs, 1, -1 do
                if node._font ~= font or i > #lines then
                    glyphs[i]:release()
                    glyphs[i] = nil
                end
            end
            for i, line in ipairs(lines) do
                glyphs[i] = glyphs[i] or g.newText(font)
                glyphs[i]:set(line)
            end
            node._plainLines = lines
            node._textAlign = node.align
            node._textHeight = #lines * font:getHeight() * font:getLineHeight() * rasterScale
            node._text, node._font, node._wrapWidth = node.text, font, width
        end
        local y = node.verticalAlign == 'top' and node._y + padding
            or node._y + (node._height - node._textHeight) / 2
        if node.verticalAlign == 'bottom' then
            y = node._y + node._height - padding - node._textHeight
        end

        local shader = g.getShader()
        g.push('all')
        g.setShader()
        if exactOffsets then
            require('source.engine.ui.drawing.modifiers').textStrokes(node, function(dx, dy)
                drawPlain(node, font, glyphs, y, width, true, dx, dy)
            end)
        end
        g.setShader(shader)
        require('source.engine.ui.drawing.modifiers').bindGradient(ui, node, 'Text')
        local c = Style.color(node, 'text')
        g.setColor(c[1], c[2], c[3], Style.alpha(node, 'text', c))
        drawPlain(node, font, glyphs, y, width, exactOffsets, 0, 0)
        g.pop()
    else
        local shader = g.getShader()
        g.push('all')
        g.setShader()
        if exactOffsets then
            require('source.engine.ui.drawing.modifiers').textStrokes(node, function(dx, dy)
                Text.draw(ui, node, dx, dy, true, true)
            end)
        end
        g.setShader(shader)
        require('source.engine.ui.drawing.modifiers').bindGradient(ui, node, 'Text')
        Text.draw(ui, node, nil, nil, false, exactOffsets)
        g.pop()
    end
end

return Text
