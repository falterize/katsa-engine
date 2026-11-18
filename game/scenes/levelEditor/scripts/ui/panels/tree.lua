-- Workspace panel: the Level tree with expanders, selection (Ctrl adds, Shift selects a range, a
-- drag over rows or over the empty space selects the rows it crosses),
-- show/hide and lock toggles, edit buttons (Duplicate, Delete, Group, Ungroup) and drag and drop:
-- drag a row onto another row to move it inside (middle of the row) or before/after it (upper or
-- lower quarter); a line or a frame shows where it will land. Rows are rebuilt only when the tree
-- or the selection changed.
local Pointer = require('../../input.pointer')
local Flow = require('../support.flow')
local Icons = require('../widgets.icons')
local Kit = require('../support.kit')
local Menus = require('../support.menus')
local TreeModel = require('../../core.treeModel')

local Tree = {}
Tree.__index = Tree

local INDENT, EXPANDER, ROW = 14, 18, 22
local CLASS_WIDTH = 74 -- room for the small class label at the right of a row
local DRAG_DISTANCE = 6
local TOOLS_WIDTH = 52 -- the eye and lock buttons at the right of a row
local TAIL = 40 -- empty space under the last row, where a drag starts a selection

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
    action('+', 26, function()
        local button = self.actions[1]
        local x, y = button:getAbsolutePosition()
        local _, height = button:getAbsoluteSize()
        state:openCreate(x, y + height + 2, nil)
    end)
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
            size = { 1, -(x + EXPANDER + 52 + CLASS_WIDTH), 0, ROW },
            text = label,
            align = 'left',
            fontSize = 13,
        }, self.scroll, 'row'))
        if selected then
            name:addTag('selected')
        end
        if node ~= state.level then
            -- The class (Mesh3D, PointLight3D, ...) as a small dim detail, right-aligned.
            local kind = add(Kit.label(ui, self.scroll, (node.className or ''):gsub('3D$', ''):gsub('2D$', ''), {
                position = { 1, -(52 + CLASS_WIDTH), 0, y },
                size = { 0, CLASS_WIDTH - 4, 0, ROW },
                align = 'right',
                fontSize = 11,
            }, 'classTag'))
            kind.interactable = false
            local eye = add(Kit.button(ui, self.scroll, '', 24, ROW, function()
                local ok, message = ops:setProperty({ node }, 'visible', nil, hidden)
                if not ok then
                    state:notify(message)
                end
            end, 'icon'))
            eye.position = { 1, -50, 0, y }
            state.panels.tooltip:register(eye, hidden and 'Hidden: click to show the object' or 'Visible: click to hide the object')
            Icons.add(ui, eye, hidden and 'eyeOff' or 'eye', 4, (ROW - 16) / 2)
            local lock = add(Kit.button(ui, self.scroll, '', 24, ROW, function()
                ops:setLocked({ node }, not ops:isLocked(node))
            end, 'icon'))
            lock.position = { 1, -25, 0, y }
            state.panels.tooltip:register(lock, ops:isLocked(node) and 'Locked: click to allow picking and editing' or 'Unlocked: click to lock the object against picking')
            Icons.add(ui, lock, ops:isLocked(node) and 'lock' or 'unlock', 4, (ROW - 16) / 2)
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, #self.rows * ROW + TAIL }
    state.styler:apply(self.scroll)
end

local function state_popupOpen(self)
    local popup = self.state.panels.popup
    return popup ~= nil and popup:isOpen()
end

local function mouse(ui)
    return (Pointer.getX() - ui.offsetX) / ui.scale, (Pointer.getY() - ui.offsetY) / ui.scale
end

-- The pointer over the list: row index (nil below the last row), the zone ('name', 'expander',
-- 'tools', 'bar') and the pointer position; nil when the list is not under the pointer
-- (another window, a pop-up or another panel covers it).
function Tree:probe()
    local ui = self.ui
    local hit = ui:hit(Pointer.getX(), Pointer.getY())
    while hit and hit ~= self.scroll do
        hit = hit.parent
    end
    if not hit then
        return nil
    end
    local mx, my = mouse(ui)
    local sx, sy, sw = Kit.rect(self.scroll)
    local localX, localY = mx - sx, my - sy + (self.scroll.scrollY or 0)
    local index = math.floor(localY / ROW) + 1
    local row = self.rows[index]
    local zone = 'name'
    if localX > sw - 8 then
        zone = 'bar'
    elseif row and row.node ~= self.state.level then
        if localX > sw - TOOLS_WIDTH then
            zone = 'tools'
        elseif row.hasChildren and localX < row.depth * INDENT + EXPANDER then
            zone = 'expander'
        end
    end
    return row and index or nil, zone, mx, my
end

-- Row under a y coordinate while dragging, clamped to the list plus one empty slot (so a drag
-- past either end still extends the range, and empty space selects nothing).
function Tree:indexAt(my)
    local _, sy = Kit.rect(self.scroll)
    local index = math.floor((my - sy + (self.scroll.scrollY or 0)) / ROW) + 1
    return math.max(1, math.min(#self.rows + 1, index))
end

-- Left button pressed over the list: select, and prepare a drag (move) or a paint (range select).
function Tree:pressed(index, zone, mx, my)
    if zone ~= 'name' then
        return
    end
    local state = self.state
    local map, selection = state.fly.map, state.selection
    local range, add = map:isDown('editorRange'), map:isDown('editorAdd')
    local row = index and self.rows[index]
    local node = row and row.node ~= state.level and row.node or nil
    local press = {
        x = mx,
        y = my,
        node = node,
        start = index or #self.rows + 1,
        base = add and selection:items() or {},
        modified = range or add,
    }
    self.press = press
    if not node then
        -- Empty space (or the Level row): a click clears, a drag paints rows.
        if not press.modified then
            selection:clear()
        end
        press.paint = true
        return
    end
    if range or add then
        self:click(node)
        press.paint = true
        if range and self.anchor then
            for i, r in ipairs(self.rows) do
                if r.node == self.anchor then
                    press.start = i
                end
            end
        end
    elseif selection:has(node) and selection:count() > 1 then
        press.deferred = true -- a click collapses to this node on release, a drag moves them all
    else
        self:click(node)
    end
end

function Tree:paint(my)
    local press, selection = self.press, self.state.selection
    local current = self:indexAt(my)
    local key = press.start * 10000 + current
    if key == press.last then
        return
    end
    press.last = key
    local items = TreeModel.slice(self.rows, press.start, current, self.state.level)
    if #press.base > 0 then
        local seen = {}
        for _, node in ipairs(items) do
            seen[node] = true
        end
        for _, node in ipairs(press.base) do
            if not seen[node] then
                items[#items + 1] = node
            end
        end
    end
    selection:set(items)
end

-- Right button over the list: a menu for the row (selecting it first) or for the empty space.
function Tree:menu(index, mx, my)
    local state = self.state
    local row = index and self.rows[index]
    local node = row and row.node ~= state.level and row.node or nil
    if node then
        if not state.selection:has(node) then
            state.selection:set({ node })
            self.anchor = node
        end
        state:popup(Menus.node(state), mx, my, { width = 220 })
    else
        state:popup(Menus.empty(state), mx, my, { width = 240 })
    end
end

function Tree:poll()
    local left, right = Pointer.isDown(1), Pointer.isDown(2)
    local pressedLeft, pressedRight = left and not self.wasLeft, right and not self.wasRight
    self.wasLeft, self.wasRight = left, right
    if state_popupOpen(self) then
        return
    end
    if pressedLeft or pressedRight then
        local index, zone, mx, my = self:probe()
        if zone == nil then
            return
        end
        if pressedLeft then
            self:pressed(index, zone, mx, my)
        elseif zone ~= 'bar' then
            self:menu(index, mx, my)
        end
    end
end

-- Where a drop would land: new parent, the sibling it goes before (nil = last), the row index
-- and the zone ('into', 'before', 'after'); nil when the pointer is outside the list.
function Tree:target(mx, my)
    local scroll = self.scroll
    local sx, sy, sw, sh = Kit.rect(scroll)
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
    if not Pointer.isDown(1) then
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
        elseif press.deferred and not press.moved then
            state.selection:set({ press.node })
            self.anchor = press.node
        end
        self:endDrag()
        self.dirty = true
        return
    end
    local mx, my = mouse(ui)
    if not press.moved and math.abs(mx - press.x) + math.abs(my - press.y) > DRAG_DISTANCE then
        press.moved = true
    end
    if press.paint then
        if press.moved then
            self:paint(my)
        end
        return
    end
    if not self.dragging then
        if press.moved then
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
    self:poll()
    self:updateDrag()
    local version = self.state.treeVersion or 0
    if (self.dirty or self.version ~= version) and not self.dragging then
        self.dirty, self.version = false, version
        self:rebuild()
    end
end

return Tree
