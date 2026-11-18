-- Workspace panel: the Level tree with expanders, selection (Ctrl adds, Shift selects a range),
-- show/hide and lock toggles. Rows are rebuilt only when the tree or the selection changed.
local Theme = require('../theme')
local TreeModel = require('../../core.treeModel')

local Tree = {}
Tree.__index = Tree

local INDENT, EXPANDER = 14, 16

local function childrenOf(node)
    return node.children
end

local function parentOf(node)
    return node.parent
end

function Tree.create(state, ui)
    local self = setmetatable({ state = state, ui = ui, rows = {}, nodes = {} }, Tree)
    self.expanded = { [state.level] = true }
    self.frame = ui:container({
        name = 'WorkspacePanel',
        position = { 0, 0, 0, Theme.top },
        size = { 0, Theme.left, 1, -(Theme.top + Theme.bottom) },
        backgroundColor = Theme.panel,
        zIndex = 5,
    }, ui.content)
    ui:create('Label', {
        position = { 0, 8, 0, 4 },
        size = { 1, -16, 0, 20 },
        fontSize = 15,
        align = 'left',
        text = 'Workspace',
        textColor = Theme.text,
        interactable = false,
    }, self.frame)
    self.scroll = ui:scroll({
        name = 'WorkspaceList',
        position = { 0, 4, 0, 28 },
        size = { 1, -8, 1, -32 },
        canvasSize = { 0, 0, 0, 0 },
        scrollBarThickness = 6,
        backgroundColor = Theme.bar,
    }, self.frame)
    self.dirty = true
    state.selection:onChange(function()
        self.dirty = true
    end)
    return self
end

function Tree:armReparent(on)
    self.reparentArmed = on
    self.dirty = true
end

function Tree:click(node)
    local state = self.state
    local map, selection = state.fly.map, state.selection
    if self.reparentArmed then
        self.reparentArmed = false
        if state.ops:reparent(selection:items(), node) then
            state.treeVersion = (state.treeVersion or 0) + 1
        end
        self.dirty = true
        return
    end
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
        local node, y = row.node, (index - 1) * Theme.row
        local selected = state.selection:has(node)
        local x = row.depth * INDENT
        if row.hasChildren then
            local expander = add(ui:button({
                position = { 0, x, 0, y },
                size = { 0, EXPANDER, 0, Theme.row },
                text = row.expanded and '-' or '+',
                fontSize = 13,
                backgroundColor = Theme.panel,
            }, self.scroll))
            expander:connect('press', function()
                self:toggle(node)
            end)
        end
        local hidden = node.visible == false
        local label = (node.name or node.className)
            .. (hidden and '  (hidden)' or '')
            .. (ops:isLocked(node) and '  (locked)' or '')
        local name = add(ui:button({
            position = { 0, x + EXPANDER, 0, y },
            size = { 1, -(x + EXPANDER + 52), 0, Theme.row },
            text = label,
            align = 'left',
            fontSize = 13,
            textColor = hidden and Theme.dim or Theme.text,
            backgroundColor = selected and Theme.rowSelected or Theme.row_,
        }, self.scroll))
        name:connect('press', function()
            self:click(node)
        end)
        if node ~= state.level then
            local eye = add(ui:button({
                position = { 1, -50, 0, y },
                size = { 0, 24, 0, Theme.row },
                text = hidden and 'h' or 'V',
                fontSize = 13,
                backgroundColor = Theme.button,
            }, self.scroll))
            eye:connect('press', function()
                local ok, message = ops:setProperty({ node }, 'visible', nil, hidden)
                if not ok then
                    state:notify(message)
                end
            end)
            local lock = add(ui:button({
                position = { 1, -25, 0, y },
                size = { 0, 24, 0, Theme.row },
                text = ops:isLocked(node) and 'L' or '-',
                fontSize = 13,
                backgroundColor = Theme.button,
            }, self.scroll))
            lock:connect('press', function()
                ops:setLocked({ node }, not ops:isLocked(node))
            end)
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, #self.rows * Theme.row }
end

function Tree:update()
    local version = self.state.treeVersion or 0
    if self.dirty or self.version ~= version then
        self.dirty, self.version = false, version
        self:rebuild()
    end
end

return Tree
