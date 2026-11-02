local readValue = require('../../math.managedValue').read
local Array = require('../../math.array')
local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
-- Shared by ScreenUI and BillboardUI canvases; no separate surface UI renderer.
local Modifiers = {}

function Modifiers.bindGradient(ui, node, target, override)
    local gradient = override
    if not gradient then
        if target == 'Text' then
            gradient = node._textGradient
        elseif target == 'Image' then
            gradient = node._imageGradient
        else
            gradient = node._backgroundGradient
        end
    end
    if not gradient then
        return
    end
    assert(not node.material, 'UIGradient and custom material cannot target the same element')
    local g = katsa.graphics
    ui.gradientShader = ui.gradientShader
        or ui.resources:own(g.newShader('assets/shaders/engine/uiGradient.glsl'))
    local shader = ui.gradientShader
    local stops = gradient:gradientStops()
    assert(Array.is(stops) and #stops >= 2 and #stops <= 16, 'UIGradient requires 2..16 colorStops')
    local colors, times = gradient._colors or {}, gradient._times or {}
    gradient._colors, gradient._times = colors, times
    local previous = -1
    for i, stop in ipairs(stops) do
        assert(
            stop.time >= 0 and stop.time <= 1 and stop.time > previous,
            'Gradient times must increase within 0..1'
        )
        assert(Array.is(stop.color) and #stop.color >= 3, 'Gradient stop requires an RGB color')
        local c = colors[i] or {}
        colors[i] = c
        for component = 1, 4 do
            local value = stop.color[component] or 1
            if component == 4 and stop.transparency ~= nil then
                value = 1 - stop.transparency
            end
            c[component] = math.max(0, math.min(1, value))
        end
        times[i] = stop.time
        previous = stop.time
    end
    local x, y = g.transformPoint(node._x, node._y)
    local x2, y2 = g.transformPoint(node._x + node._width, node._y + node._height)
    local angle = math.rad(gradient.rotation)
    gradient._uniformOrigin, gradient._uniformExtent =
        gradient._uniformOrigin or {}, gradient._uniformExtent or {}
    gradient._uniformDirection, gradient._uniformOffset =
        gradient._uniformDirection or {}, gradient._uniformOffset or {}
    local origin, extent = gradient._uniformOrigin, gradient._uniformExtent
    local direction, offset = gradient._uniformDirection, gradient._uniformOffset
    origin[1], origin[2] = x, y
    extent[1], extent[2] = x2 - x, y2 - y
    direction[1], direction[2] = math.cos(angle), math.sin(angle)
    local o = readValue(gradient.offset)
    offset[1] = o[1] + o[2] / math.max(0.0001, node._width)
    offset[2] = o[3] + o[4] / math.max(0.0001, node._height)
    shader:send('gradientOrigin', origin)
    shader:send('gradientExtent', extent)
    shader:send('gradientDirection', direction)
    shader:send('gradientOffset', offset)
    shader:send('gradientCount', #stops)
    shader:send('gradientColors', unpack(colors, 1, #stops))
    shader:send('gradientTimes', unpack(times, 1, #stops))
    shader:send('gradientOpacity', 1 - math.max(0, math.min(1, gradient.transparency)))
    g.setShader(shader)
end

function Modifiers.thickness(stroke, node, limit)
    local v = readValue(stroke.thickness)
    assert(v[1] >= 0 and v[2] >= 0, 'UIStroke thickness components must be nonnegative')
    return math.min(limit, math.max(0, math.min(node._width, node._height) * v[1] + v[2]))
end

function Modifiers.strokeGradient(stroke, node)
    local gradient = stroke._backgroundGradient or stroke._textGradient
    if gradient then
        Modifiers.bindGradient(node.ui, node, 'Background', gradient)
    end
end

function Modifiers.drawBorders(node)
    local g = katsa.graphics
    for _, stroke in ipairs(node.children) do
        if
            stroke:isA('UIStroke')
            and stroke.target == 'Border'
            and require('source.engine.ui').isWorking(stroke)
        then
            local thickness = Modifiers.thickness(stroke, node, 64)
            if thickness > 0 then
                g.push('all')
                g.setShader()
                Modifiers.strokeGradient(stroke, node)
                g.setLineWidth(thickness)
                local c = stroke.color
                g.setColor(
                    c[1],
                    c[2],
                    c[3],
                    (c[4] or 1)
                        * (1 - stroke.transparency)
                        * (node:isA('CanvasGroup') and 1 or (1 - (node.transparency or 0)))
                )
                local inset = thickness / 2
                local w, h =
                    math.max(0, node._width - 2 * inset), math.max(0, node._height - 2 * inset)
                g.rectangle(
                    'line',
                    node._x + inset,
                    node._y + inset,
                    w,
                    h,
                    math.max(0, (node._radius or 0) - inset)
                )
                g.pop()
            end
        end
    end
end

function Modifiers.textStrokes(node, draw)
    local active = false
    for _, stroke in ipairs(node.children) do
        if
            stroke:isA('UIStroke')
            and stroke.target == 'Text'
            and require('source.engine.ui').isWorking(stroke)
        then
            active = true
            break
        end
    end
    if not active then
        return
    end
    local ui = node.ui
    local g = katsa.graphics
    if not ui.outlineMaskShader then
        ui.outlineMaskShader =
            ui.resources:own(g.newShader('assets/shaders/engine/uiOutlineMask.glsl'))
    end
    local comparison, value = g.getStencilTest()
    local level = ui._stencilLevel or 0
    g.push('all')
    g.setShader(ui.outlineMaskShader)
    -- A sentinel cannot promote pixels outside an ancestor into its active level.
    g.stencil(function()
        draw(0, 0)
    end, 'replace', 255, true)
    g.setStencilTest('equal', level)
    g.setShader()
    local g = katsa.graphics
    for _, stroke in ipairs(node.children) do
        if
            stroke:isA('UIStroke')
            and stroke.target == 'Text'
            and require('source.engine.ui').isWorking(stroke)
        then
            local thickness = Modifiers.thickness(stroke, node, 8)
            g.push('all')
            g.setShader()
            Modifiers.strokeGradient(stroke, node)
            local c = stroke.color
            g.setColor(
                c[1],
                c[2],
                c[3],
                (c[4] or 1)
                    * (1 - stroke.transparency)
                    * (node:isA('CanvasGroup') and 1 or (1 - (node.transparency or 0)))
            )
            local steps = math.max(8, math.ceil(thickness * 4))
            if thickness > 0 then
                for i = 1, steps do
                    local angle = i * 2 * math.pi / steps
                    draw(math.cos(angle) * thickness, math.sin(angle) * thickness)
                end
            end
            g.pop()
        end
    end
    g.setShader(ui.outlineMaskShader)
    if level == 0 then
        g.stencil(function()
            draw(0, 0)
        end, 'replace', 0, true)
    else
        -- Rebuild ancestors: glyph pixels may have crossed several rounded masks.
        g.setScissor()
        g.setStencilTest()
        g.setShader()
        g.stencil(ui._clearStencil, 'replace', 0, false)
        for _, ancestor in ipairs(ui._stencilStack or {}) do
            ui._stencilNode = ancestor
            g.stencil(ui._stencilRectangle, 'increment', 1, true)
        end
    end
    g.pop()
    g.setStencilTest(comparison, value)
end

return Modifiers
