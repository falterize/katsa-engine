local Layout = require('source.engine.ui.layout.metrics')
local Rich = require('source.engine.ui.drawing.richText')
local Style = require('source.engine.ui.style')

local count = 0

local function check(ok, message)
    assert(ok, message)
    count = count + 1
    print('PASS ' .. message)
end
local node =
    { size = { 0.5, 10, 0.25, 4 }, position = { 0.5, 0, 0.5, 0 }, anchorPoint = { 0.5, 0.5 } }
local x, y, w, h = Layout.rect(node, 200, 100)
check(
    w == 110 and h == 29 and x == 45 and y == 35.5,
    'UDim2 scale/offset and anchors use parent dimensions'
)
node.sizeRelativeTo = 'XX'
x, y, w, h = Layout.rect(node, 200, 100)
check(w == 110 and h == 54 and y == 23, 'Relative XX sizes both axes from parent width')
node.sizeRelativeTo = 'YY'
x, y, w, h = Layout.rect(node, 200, 100)
check(w == 60 and h == 29, 'Relative YY sizes both axes from parent height')
node.positionRelativeTo = 'XX'
x, y = Layout.rect(node, 200, 100)
check(x == 70 and y == 85.5, 'Position can independently choose its relative axes')
check(not pcall(Layout.resolve, { 1, 2, 3 }, 100, 100), 'Invalid UDim2 fails clearly')
check(
    not pcall(Layout.resolve, { 0, 0, 0, 0 }, 100, 100, 'ZZ'),
    'Invalid relative mode fails clearly'
)
local old = { x = 10, y = 20, width = 30, height = 40 }
x, y, w, h = Layout.rect(old, 200, 100)
check(x == 10 and y == 20 and w == 30 and h == 40, 'Legacy pixel coordinates remain compatible')
local runs = Rich.parse(
    '<b>Bold <i>both</i></b> plain <font color="#FF8000" size="30">orange</font><br/><u>under</u>',
    true
)
check(
    runs[1].b and runs[2].b and runs[2].i and not runs[3].b,
    'RichText nested formatting restores the outer state'
)
check(
    runs[4].size == 30 and runs[4].color[1] == 1 and runs[4].color[3] == 0,
    'RichText font color and size parse explicit values'
)
check(runs[5].text == '\n' and runs[6].u, 'RichText line breaks and underline parse')
check(Rich.parse('&lt;b&gt; &amp;', true)[1].text == '<b> &', 'Escaped markup stays plain text')
check(not pcall(Rich.parse, '<b>bad</i>', true), 'Malformed nesting fails with a clear error')
check(
    Rich.parse('<b>literal</b>', false)[1].text == '<b>literal</b>',
    'Disabled RichText preserves literal text'
)
local styled = {
    backgroundColor = { 0.1, 0.2, 0.3 },
    backgroundTransparency = 0.3,
    textColor = { 1, 1, 1 },
    textTransparency = 0.6,
    transparency = 0.2,
    isA = function()
        return false
    end,
}
check(
    math.abs(Style.alpha(styled, 'background', styled.backgroundColor) - 0.56) < 1e-9,
    'Background channel combines independent opacity and legacy element opacity'
)
check(
    math.abs(Style.alpha(styled, 'text', styled.textColor) - 0.32) < 1e-9,
    'Text transparency stays independent of background transparency'
)
styled.backgroundTransparency = nil
check(
    math.abs(Style.alpha(styled, 'background', { 1, 1, 1, 0.5 }) - 0.4) < 1e-9,
    'Legacy RGBA remains supported without a new channel transparency'
)
local Quality = require('source.engine.graphics.quality.renderQuality')
local d, aa =
    Quality.resolve(800, 360, 3, 4, { texturesize = 8192, canvasmsaa = 8 }, 4194304, 100663296)
check(d == 3 and aa == 4, 'Quality retains physical DPI and MSAA inside allocation limits')
d, aa = Quality.resolve(
    1600,
    900,
    3,
    4,
    { texturesize = 8192, canvasmsaa = 8 },
    4194304,
    32 * 1024 * 1024
)
check(
    1600 * 900 * d * d * (8 * math.max(1, aa) + 4) <= 32 * 1024 * 1024 + 1,
    'Quality lowers MSAA/density to respect a memory budget'
)
d, aa = Quality.resolve(800, 600, 1, 4, { texturesize = 8192, canvasmsaa = 0 }, 4194304, 100663296)
check(aa == 0 and d == 1, 'Unsupported MSAA retains a valid single-sample render target')
print('PASSED ' .. count .. ' UI layout/style/markup assertions')
