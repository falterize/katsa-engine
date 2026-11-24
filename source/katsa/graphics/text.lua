-- Fonts and text drawing.

local FontModule = require('source.katsa.graphics.font')
local State = require('source.katsa.graphics.state')
local Batch = require('source.katsa.graphics.batch')
local S = State.S
local G = State.G

function G.newFont(...)
    State.requireReady()
    return FontModule.new(...)
end

function G.newText(font, text)
    State.requireReady()
    return FontModule.newText(font, text)
end

function G.setFont(font)
    S.font = font
end

function G.getFont()
    if not S.font then
        S.font = FontModule.new(12)
    end
    return S.font
end

-- Colored text is { {r,g,b,a}, 'text', {r,g,b,a}, 'more' }.
local function eachSegment(text, fn)
    if type(text) == 'table' then
        local color
        for i = 1, #text do
            local item = text[i]
            if type(item) == 'table' then
                color = item
            else
                fn(item, color)
            end
        end
    else
        fn(tostring(text), nil)
    end
end

-- Glyph bitmaps are rasterized for physical pixels; drawn at a fractional pixel the linear filter
-- smears them ("soft" text). With a plain translation the quads are placed on whole physical pixels.
local function snapsToPixels(matrix)
    return matrix[1] == 1 and matrix[2] == 0 and matrix[3] == 0 and matrix[4] == 1
end

local function emitLine(font, line, matrix, ox, oy)
    local dpi = font._dpi
    local snap = snapsToPixels(matrix)
    -- The line origin in physical pixels, so rounding keeps glyphs on the same pixel grid.
    local originX, originY = matrix[5] * dpi, matrix[6] * dpi
    local quads, count = font:_lineQuads(line)
    local addQuad = Batch.addQuad
    for index = 0, count - 1 do
        local at = index * 9
        local w, h = quads[at + 4], quads[at + 5]
        local px, py = ox + quads[at + 2], oy + quads[at + 3]
        if snap then
            px = math.floor(originX + px + 0.5) - originX
            py = math.floor(originY + py + 0.5) - originY
        end
        local x0, y0 = px / dpi, py / dpi
        local x1, y1 = (px + w) / dpi, (py + h) / dpi
        addQuad(quads[at + 1], x0, y0, x1, y0, x0, y1, x1, y1, quads[at + 6], quads[at + 7], quads[at + 8], quads[at + 9], matrix)
    end
end

local function printLines(font, lines, matrix, alignWidth, align)
    local lineAdvance = font._height * font._lineHeight
    for index, line in ipairs(lines) do
        local offset = 0
        if alignWidth then
            local w = font:getWidth(line) * font._dpi
            if align == 'right' then
                offset = alignWidth * font._dpi - w
            elseif align == 'center' then
                offset = (alignWidth * font._dpi - w) / 2
            end
        end
        emitLine(font, line, matrix, offset, (index - 1) * lineAdvance)
    end
end

local function splitLines(text)
    local lines = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end
    return lines
end

local function printColored(text, matrix, draw)
    local saved = { unpack(S.color) }
    local multiplied = saved
    eachSegment(text, function(segment, color)
        if color then
            S.color = {
                color[1] * multiplied[1],
                color[2] * multiplied[2],
                color[3] * multiplied[3],
                (color[4] or 1) * multiplied[4],
            }
        else
            S.color = saved
        end
        draw(segment)
    end)
    S.color = saved
end

function G.print(text, x, y, angle, sx, sy, ox, oy, kx, ky)
    State.requireReady()
    local font = G.getFont()
    local matrix = Batch.composed(x, y, angle, sx, sy, ox, oy, kx, ky)
    -- continuing colored segments on the same line advance horizontally
    local cursor = 0
    local function draw(segment)
        local lines = splitLines(segment)
        local m = matrix
        if cursor ~= 0 then
            m = {
                matrix[1],
                matrix[2],
                matrix[3],
                matrix[4],
                matrix[1] * cursor + matrix[5],
                matrix[2] * cursor + matrix[6],
            }
        end
        printLines(font, lines, m)
        if #lines == 1 then
            cursor = cursor + font:getWidth(lines[1])
        else
            cursor = font:getWidth(lines[#lines])
        end
    end
    if type(text) == 'table' then
        printColored(text, matrix, draw)
    else
        draw(tostring(text))
    end
end

function G.printf(text, x, y, limit, align, angle, sx, sy, ox, oy, kx, ky)
    State.requireReady()
    local font = G.getFont()
    local matrix = Batch.composed(x, y, angle, sx, sy, ox, oy, kx, ky)
    local _, lines = font:getWrap(text, limit)
    local plainText = FontModule.plain(text)
    if type(text) == 'table' then
        printColored(text, matrix, function() end)
        -- colors apply per wrapped text run; use the first color for the whole paragraph
        local first
        for _, item in ipairs(text) do
            if type(item) == 'table' then
                first = item break
            end
        end
        local saved = { unpack(S.color) }
        if first then
            S.color = {
                first[1] * saved[1],
                first[2] * saved[2],
                first[3] * saved[3],
                (first[4] or 1) * saved[4],
            }
        end
        printLines(font, lines, matrix, limit, align or 'left')
        S.color = saved
    else
        printLines(font, lines, matrix, limit, align or 'left')
    end
end
