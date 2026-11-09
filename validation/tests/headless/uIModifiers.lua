-- Instruments shared UI rendering; does not verify GPU pixels.
require('validation.tests.integration.luaCompatibility')
local count, rectangles, texts, shader, uniforms, stack = 0, {}, 0, nil, {}, {}

local function check(ok, msg)
    assert(ok, msg)
    count = count + 1
    print('PASS ' .. msg)
end

local function noop() end

local function font()
    return {
        setFilter = noop,
        getHeight = function()
            return 18
        end,
        getLineHeight = function()
            return 1
        end,
        getWrap = function(_, text, width)
            return width, { text }
        end,
    }
end
local g = {
    setDepthMode = noop,
    getDPIScale = function()
        return 1
    end,
    newFont = font,
    newShader = function()
        return {
            release = noop,
            send = function(_, name, ...)
                uniforms[name] = { ... }
            end,
        }
    end,
    transformPoint = function(x, y)
        return x, y
    end,
    setShader = function(v)
        shader = v
    end,
    getShader = function()
        return shader
    end,
    push = function()
        stack[#stack + 1] = { shader = shader }
    end,
    pop = function()
        shader = table.remove(stack).shader
    end,
    setFont = noop,
    setColor = noop,
    setLineWidth = noop,
    getStencilTest = function()
        return nil
    end,
    setStencilTest = noop,
    setScissor = noop,
    intersectScissor = noop,
    translate = noop,
    scale = noop,
    origin = noop,
    setCanvas = noop,
    clear = noop,
    setBlendMode = noop,
    stencil = function(callback)
        callback()
    end,
    rectangle = function(mode, x, y, w, h, r)
        rectangles[#rectangles + 1] = { mode, x, y, w, h, r }
    end,
    printf = function()
        texts = texts + 1
    end,
    draw = noop,
    newCanvas = function(w, h)
        return {
            getWidth = function()
                return w
            end,
            getHeight = function()
                return h
            end,
            release = noop,
        }
    end,
}
katsa = { graphics = g }
local resources = {
    own = function(_, v)
        return v
    end,
    releaseOwned = function(_, v)
        v:release()
    end,
}
local UI = require('source.engine.ui')

local ui = UI.new(400, 240, resources)
local button = ui:create(
    'Button',
    { x = 20, y = 30, width = 180, height = 60, text = 'Gradient', color = { 1, 1, 1, 1 } },
    ui.content
)
local corner = ui:create('UICorner', { cornerRadius = 18 }, button)
local background = ui:create('UIGradient', { target = 'Background' }, button)
local foreground = ui:create('UIGradient', { target = 'Text' }, button)
local border = ui:create('UIStroke', { target = 'Border', thickness = 2 }, button)
local text = ui:create('UIStroke', { target = 'Text', thickness = 1 }, button)
ui:layout()
check(
    button._radius == 18
        and button._backgroundGradient == background
        and button._textGradient == foreground,
    'Layout applies independent background/text gradients and rounded corner'
)
ui:draw()
local outline
for _, r in ipairs(rectangles) do
    if r[1] == 'line' then
        outline = r
    end
end
check(
    outline and outline[2] == 21 and outline[4] == 178 and outline[6] == 17,
    'Border stroke tracks the inset rounded edge'
)
check(texts == 10, 'Text stroke draws bounded offsets separately from border stroke')
check(
    uniforms.gradientOrigin[1][1] == 20 and uniforms.gradientExtent[1][1] == 180,
    'Gradient uniforms use transformed element coordinates'
)
local rev = ui:changed()
background.colorStops[2].color[1] = 0.7
check(ui:changed() > rev, 'In-place color-stop edit invalidates cached UI')
rev = ui:changed()
background.offset[1] = 0.2
check(ui:changed() > rev, 'In-place gradient offset edit invalidates cached UI')
check(ui:changed() == ui:changed(), 'Unchanged modifier properties keep their revision')
button.size = { 0, 80, 0, 60 }
corner.radius = { 0, 50 }
ui:layout()
check(button._radius == 30, 'Corner radius follows resized parent bounds')
text.enabled = false
texts = 0
ui:draw()
check(texts == 1, 'Disabled text stroke leaves only the normal text pass')
background.enabled = false
ui:layout()
check(button._backgroundGradient == nil, 'Disabled gradient clears prior layout effect')
local replacement = ui:create('UIGradient', { target = 'Background' }, button)
ui:layout()
check(
    button._backgroundGradient == replacement,
    'Last enabled gradient per target wins deterministically'
)
replacement:destroy()
ui:layout()
check(button._backgroundGradient == nil, 'Destroying modifier removes its rendering effect')
check(
    not pcall(ui.create, ui, 'UIStroke', {}, corner),
    'Modifiers cannot be nested under another modifier'
)
local group = ui:canvasGroup({ width = 240, height = 120, transparency = 0.5 })
local child = ui:create(
    'Label',
    { width = 180, height = 50, text = 'Group', color = { 1, 1, 1, 1 } },
    group
)
ui:create('UIGradient', {}, child)
ui:create('UIStroke', { target = 'Border' }, child)
ui:draw()
check(group._groupCanvas ~= nil, 'Modifiers share the CanvasGroup render path')
local owner = button.parent
local props = require('source.engine.editor.inspectors.properties')

local path = props.parentPath(button)
check(path == 'ScreenUI / HUD', 'Workspace parent path contains the complete ancestry')
local listed = props.list(button)
check(
    listed[1].key == 'parent' and listed[1].readOnly,
    'Workspace exposes parent as a read-only property'
)
check(
    not props.set({}, button, listed[1], 'changed'),
    'Read-only parent cannot be assigned through property editor'
)
button:destroy()
check(
    corner.destroyed and border.destroyed and foreground.destroyed,
    'Parent destruction cleans modifier nodes'
)
ui:release()
print(
    'PASSED ' .. count .. ' instrumented UI-modifier and parent-path assertions; no pixel testing'
)
