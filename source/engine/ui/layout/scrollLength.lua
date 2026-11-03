local ipairs = require('../../math.array').ipairs
local Canvas = require('./scrollCanvas')

local Length = {}

local function sample(state, value)
    local index = state.cursor + 1
    state.cursor = index
    if state.values[index] ~= value then
        state.values[index], state.dirty = value, true
    end
end

local function visit(node, children, state)
    for _, child in ipairs(children) do
        local visible = child:isA('UINode') and child.visible and not child.modifier
        sample(state, child)
        sample(state, visible)
        if visible then
            local x = child._x - node._x - node._windowX + node.scrollX + (node._overX or 0)
            local y = child._y - node._y + node.scrollY + (node._overY or 0)
            sample(state, x)
            sample(state, y)
            sample(state, child._width)
            sample(state, child._height)
            state.right = math.max(state.right, x + child._width)
            state.bottom = math.max(state.bottom, y + child._height)
            if not child.clip then
                visit(node, child.children, state)
            end
        end
    end
end

function Length.prepare(node)
    Canvas.sync(node)
    return Canvas.window(node)
end

function Length.update(node)
    local autoX, autoY = Canvas.sync(node)
    local state = node._lengthState
    if not state then
        state = { values = {} }
        node._lengthState = state
    end
    state.cursor, state.dirty, state.right, state.bottom = 0, false, 0, 0
    if autoX or autoY then
        sample(state, node._windowWidth)
        sample(state, node._windowHeight)
        sample(state, node.contentPadding)
        visit(node, node.children, state)
        if #state.values ~= state.cursor then
            state.dirty = true
            for index = #state.values, state.cursor + 1, -1 do
                state.values[index] = nil
            end
        end
        if state.dirty then
            node._lengthCalculations = (node._lengthCalculations or 0) + 1
        end
    end
    local size, resolved = node.canvasSize, node.absoluteCanvasSize
    resolved[1] =
        math.max(size[1] * node._width + size[2], autoX and state.right + node.contentPadding or 0)
    resolved[2] = math.max(
        size[3] * node._height + size[4],
        autoY and state.bottom + node.contentPadding or 0
    )
    if node.automaticLength then
        -- The old length API reports measured height and can shrink with content.
        resolved[2] = state.bottom + node.contentPadding
        node.length = math.max(0, resolved[2])
        node.canvasSize[4] = node.length
    end
    local resized = Canvas.window(node)
    return Canvas.clamp(node) or resized
end

return Length
