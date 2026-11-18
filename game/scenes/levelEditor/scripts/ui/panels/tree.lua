-- Workspace panel: the Level tree with expanders, selection (Ctrl adds, Shift selects a range),
-- show/hide and lock toggles, edit buttons (Duplicate, Delete, Group, Ungroup) and drag and drop:
-- drag a row onto another row to move it inside (middle of the row) or before/after it (upper or
-- lower quarter); a line or a frame shows where it will land. Rows are rebuilt only when the tree
-- or the selection changed.
local Flow = require('../flow')
local Kit = require('../kit')
local TreeModel = require('../../core.treeModel')

local Tree = {}
Tree.__index = Tree

local INDENT, EXPANDER, ROW = 14, 18, 22
local DRAG_DISTANCE = 6

local function childrenOf(node)
    return node.children
end

local function parentOf(node)
    return node.parent
end

function Tree.create(state, ui, frame)
    local self = setmetatable({ state = state, ui = ui, frame = frame, rows = {}, nodes = {} }, Tree)
    self.expanded = { [state.level] = true }
    Kit.label(ui, frame, 'Workspace', { position = { 0, 8, 0, 4 }, size = { 1, -16, 0, 20 } }, 'title')
    self.actions, self.items = {}, {}
    local function action(text, width, run)
        local button = Kit.button(ui, frame, text, width, 22, run, 'tool')
        self.actions[#self.actions + 1] = button
        self.items[#self.items + 1] = { w = width }
    end
    local ops, selection = state.ops, state.selection
    action('Duplicate', 66, function()
        ops:duplicate(selection:items())
    end)
    action('Delete', 52, function()
        ops:delete(selection:items())
    end)
    action('Group', 52, function()
        ops:group(selection:items())
    end)
    action('Ungroup', 60, function()
        local node = selection:primary()
        if node then
            local ok, message = ops:ungroup(node)
            if not ok then
                state:notify(message)
            end
        end
    end)
    self.scroll = Kit.make(ui, 'ScrollFrame', {
        name = 'WorkspaceList',
        position = { 0, 4, 0, 60 },
        size = { 1, -8, 1, -64 },
        canvasSize = { 0, 0, 0, 0 },
        scrollBarThickness = 6,
    }, frame, 'list')
    self.markLine = Kit.make(ui, 'Frame', { size = { 1, 0, 0, 2 }, visible = false, zIndex = 20 }, self.scroll, 'dropLine')
    self.markInto = Kit.make(ui, 'Frame', { size = { 1, 0, 0, ROW }, visible = false, zIndex = 19 }, self.scroll, 'dropInto')
    self.dirty = true
    state.selection:onChange(function()
        self.dirty = true
    end)
    return self
end

-- Wraps the edit buttons for the panel width and fits the list below them.
function Tree:resize(width, height)
    local positions, rowsHeight = Flow.place(self.items, width - 8, 4, 22, 0)
    for index, button in ipairs(self.actions) do
        button.position = { 0, 4 + positions[index].x, 0, 26 + positions[index].y }
    end
    local top = 26 + rowsHeight + 6
    self.scroll.position = { 0, 4, 0, top }
    self.scroll.size = { 0, width - 8, 0, height - top - 4 }
end

function Tree:click(node)
    local state = self.state
    local map, selection = state.fly.map, state.selection
    if node == state.level then
        selection:clear()
    elseif map:isDown('editorRange') and self.anchor and not self.anchor.destroyed then
        local range = TreeModel.range(self.rows, self.anchor, node)
        selection:set(range or { node })
    elseif map:isDown('editorAdd') then
        selection:toggle(node)
        self.anchor = node
    else
        selection:set({ node })
        self.anchor = node
    end
end

function Tree:toggle(node)
    self.expanded[node] = not self.expanded[node] or nil
    self.dirty = true
end

function Tree:rebuild()
    for _, widget in ipairs(self.nodes) do
        if not widget.destroyed then
            widget:destroy()
        end
    end
    self.nodes = {}
    local state, ui = self.state, self.ui
    -- A selected node's ancestors open so the selection is always visible.
    for _, node in ipairs(state.selection.list) do
        local parent = node.parent
        while parent do
            self.expanded[parent] = true
            parent = parent.parent
        end
    end
    self.rows = TreeModel.flatten(state.level, childrenOf, self.expanded, self.rows)
    local ops = state.ops
    local function add(widget)
        self.nodes[#self.nodes + 1] = widget
        return widget
    end
    for index, row in ipairs(self.rows) do
        local node, y = row.node, (index - 1) * ROW
        local selected = state.selection:has(node)
        local x = row.depth * INDENT
        if row.hasChildren then
            local expander = add(Kit.button(ui, self.scroll, row.expanded and '-' or '+', EXPANDER, ROW, function()
                self:toggle(node)
            end, 'icon'))
            expander.position = { 0, x, 0, y }
        end
        local hidden = node.visible == false
        local label = (node.name or node.className)
            .. (hidden and '  (hidden)' or '')
            .. (ops:isLocked(node) and '  (locked)' or '')
        local name = add(Kit.make(ui, 'Button', {
            position = { 0, x + EXPANDER, 0, y },
            size = { 1, -(x + EXPANDER + 52), 0, ROW },
            text = label,
            align = 'left',
            fontSize = 13,
        }, self.scroll, 'row'))
        if selected then
            name:addTag('selected')
        end
        name:connect('press', function()
            self:click(node)
            if node ~= state.level then
                local ui_ = self.ui
                self.press = {
                    node = node,
                    x = (katsa.mouse.getX() - ui_.offsetX) / ui_.scale,
                    y = (katsa.mouse.getY() - ui_.offsetY) / ui_.scale,
                }
            end
        end)
        if node ~= state.level then
            local eye = add(Kit.button(ui, self.scroll, hidden and 'h' or 'V', 24, ROW, function()
                local ok, message = ops:setProperty({ node }, 'visible', nil, hidden)
                if not ok then
                    state:notify(message)
                end
            end, 'icon'))
            eye.position = { 1, -50, 0, y }
            local lock = add(Kit.button(ui, self.scroll, ops:isLocked(node) and 'L' or '-', 24, ROW, function()
                ops:setLocked({ node }, not ops:isLocked(node))
            end, 'icon'))
            lock.position = { 1, -25, 0, y }
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, #self.rows * ROW }
    state.styler:apply(self.scroll)
end

local function mouse(ui)
    return (katsa.mouse.getX() - ui.offsetX) / ui.scale, (katsa.mouse.getY() - ui.offsetY) / ui.scale
end

-- Where a drop would land: new parent, the sibling it goes before (nil = last), the row index
-- and the zone ('into', 'before', 'after'); nil when the pointer is outside the list.
function Tree:target(mx, my)
    local scroll = self.scroll
    local sx, sy = scroll:getAbsolutePosition()
    local sw, sh = scroll:getAbsoluteSize()
    if mx < sx or mx > sx + sw or my < sy or my > sy + sh then
        return nil
    end
    local state = self.state
    local localY = my - sy + (scroll.scrollY or 0)
    local index = math.floor(localY / ROW) + 1
    local row = self.rows[index]
    if not row then
        return state.level, nil, #self.rows, 'into'
    end
    local node = row.node
    local fraction = (localY - (index - 1) * ROW) / ROW
    if node == state.level or (fraction >= 0.25 and fraction <= 0.75) then
        return node, nil, index, 'into'
    end
    local parent = node.parent
    if fraction < 0.25 then
        return parent, node, index, 'before'
    end
    local moving = self.dragSet
    local after
    local seen = false
    for _, sibling in ipairs(parent.children) do
        if seen and not moving[sibling] then
            after = sibling
            break
        end
        seen = seen or sibling == node
    end
    return parent, after, index, 'after'
end

function Tree:valid(parent)
    local any = false
    for node in pairs(self.dragSet) do
        if node ~= self.state.level and TreeModel.canReparent(node, parent, parentOf) then
            any = true
        elseif node ~= self.state.level then
            return false
        end
    end
    return any
end

function Tree:beginDrag()
    local state = self.state
    local items = state.selection:has(self.press.node) and state.selection:items() or { self.press.node }
    self.dragSet = {}
    for _, node in ipairs(items) do
        self.dragSet[node] = true
    end
    self.dragging = true
    local text = #items > 1 and (#items .. ' objects') or (self.press.node.name or 'object')
    self.ghost = Kit.make(self.ui, 'Label', {
        size = { 0, 150, 0, 20 },
        text = text,
        fontSize = 13,
        zIndex = 60,
        interactable = false,
        position = { 0, 0, 0, 0 },
    }, self.ui.content, 'text')
    self.ghost.backgroundColor = { 0.275, 0.51, 0.82 }
    self.ghost.backgroundTransparency = 0.25
end

function Tree:endDrag()
    self.press, self.dragging, self.dragSet = nil, false, nil
    if self.ghost and not self.ghost.destroyed then
        self.ghost:destroy()
    end
    self.ghost = nil
    self.markLine.visible, self.markInto.visible = false, false
end

function Tree:updateDrag()
    local press = self.press
    if not press then
        return
    end
    local ui, state = self.ui, self.state
    if not katsa.mouse.isDown(1) then
        if self.dragging and self.drop then
            local drop = self.drop
            if drop.parent and self:valid(drop.parent) then
                local items = {}
                for node in pairs(self.dragSet) do
                    items[#items + 1] = node
                end
                -- Keep the tree order of the dragged nodes.
                local order = {}
                for index, row in ipairs(self.rows) do
                    order[row.node] = index
                end
                table.sort(items, function(a, b)
                    return (order[a] or 0) < (order[b] or 0)
                end)
                if state.ops:reparent(items, drop.parent, drop.before) then
                    self.expanded[drop.parent] = true
                    state.treeVersion = (state.treeVersion or 0) + 1
                end
            end
        end
        self:endDrag()
        self.dirty = true
        return
    end
    local mx, my = mouse(ui)
    if not self.dragging then
        if math.abs(mx - press.x) + math.abs(my - press.y) > DRAG_DISTANCE then
            self:beginDrag()
        else
            return
        end
    end
    self.ghost.position = { 0, mx + 14, 0, my + 4 }
    local parent, before, index, zone = self:target(mx, my)
    self.drop = nil
    local ok = parent ~= nil and self:valid(parent)
    self.markLine.visible, self.markInto.visible = false, false
    if ok then
        self.drop = { parent = parent, before = before }
        if zone == 'into' then
            self.markInto.position = { 0, 0, 0, (index - 1) * ROW }
            self.markInto.visible = true
        else
            local y = (zone == 'before' and (index - 1) or index) * ROW - 1
            self.markLine.position = { 0, 0, 0, y }
            self.markLine.visible = true
        end
    end
end

function Tree:update()
    self:updateDrag()
    local version = self.state.treeVersion or 0
    if (self.dirty or self.version ~= version) and not self.dragging then
        self.dirty, self.version = false, version
        self:rebuild()
    end
end

return Tree
