-- Explorer rows for the Workspace tree. Each row has a fold chevron, a class color chip, the node
-- name and its class. Depth indents without limit; the list scrolls on both axes, so deep nodes
-- keep their full width and stay offset from their parents.
local Tree = require('./traversal')

local WorkspaceRows = {}

local ROW = 36
local INDENT = 16
local ROW_COLOR = { 0.06, 0.09, 0.13 }
local ROW_ALT = { 0.05, 0.075, 0.11 }
local SELECTED = { 0.1, 0.32, 0.45 }
local NAME_WIDTH = 8.8 -- average pixels per character at the name font size (14)
local CLASS_WIDTH = 7.6 -- ... and at the class font size (12)

-- Class families -> chip colors, so a long tree can be scanned by color.
local FAMILIES = {
    { { 'Mesh', 'Model', 'Decal', 'Surface' }, { 0.95, 0.62, 0.25 } },
    { { 'Body', 'Collider', 'Constraint', 'Physics' }, { 0.9, 0.4, 0.42 } },
    { { 'Light' }, { 0.98, 0.85, 0.35 } },
    { { 'Camera' }, { 0.4, 0.82, 0.95 } },
    { { 'Sound', 'Audio' }, { 0.72, 0.5, 0.95 } },
    { { 'Particle' }, { 0.95, 0.5, 0.75 } },
    { { 'Animat', 'Ramp', 'Track' }, { 0.35, 0.85, 0.7 } },
    {
        {
            'Frame',
            'Label',
            'Button',
            'Scroll',
            'TextBox',
            'Image',
            'Slider',
            'UI',
            'World2D',
            'Canvas',
            'Viewport',
            'Joystick',
        },
        { 0.45, 0.85, 0.5 },
    },
    { { 'Settings', 'Folder', 'Environment', 'Shader' }, { 0.6, 0.65, 0.72 } },
}
local DEFAULT_CHIP = { 0.4, 0.62, 0.95 }

function WorkspaceRows.chipColor(className)
    className = className or ''
    for _, family in ipairs(FAMILIES) do
        for _, pattern in ipairs(family[1]) do
            if className:find(pattern, 1, true) then
                return family[2]
            end
        end
    end
    return DEFAULT_CHIP
end

local function label(row)
    return (row.node.name or row.node.className or 'Node')
end

function WorkspaceRows.install(Workspace)
    function Workspace:refreshTree()
        self.rows = Tree.rows(
            { self.scene.world.root, self.settingsRoot },
            self.collapsed,
            self.group,
            self.query
        )
        -- Content width: the deepest indent plus its name and class text.
        local widest = 0
        for _, row in ipairs(self.rows) do
            local text = #label(row) * NAME_WIDTH + #(row.node.className or 'Node') * CLASS_WIDTH
            widest = math.max(widest, row.depth * INDENT + 96 + text)
        end
        self.contentWidth = widest
        self.tree.scrollingDirection = 'XY'
        self.tree.scrollBarThickness = 5
        self.tree.horizontalScrollBarInset = 'ScrollBar'
        self.tree.verticalScrollBarInset = 'ScrollBar'
        local viewWidth = self.tree._width or 0
        self.tree.canvasSize = { 0, math.max(widest, viewWidth), 0, #self.rows * ROW }
        self.ui:scrollBy(self.tree, 0)
        self:renderRows()
    end

    function Workspace:renderRows()
        local height = self.tree._height or math.max(1, self.ui.height - 174)
        local first = math.max(1, math.floor(self.tree.scrollY / ROW) + 1)
        local count = math.ceil(height / ROW) + 1
        local width = math.max(self.contentWidth or 0, self.tree._width or 0)
        for i = 1, count do
            local item = self.rowPool[i]
            if not item then
                item = {}
                item.background = self.ui:button({
                    size = { 0, width, 0, ROW - 2 },
                    fontSize = 13,
                    backgroundColor = ROW_COLOR,
                }, self.tree)
                item.background:connect('press', function()
                    if item.row then
                        self:select(item.row.node)
                    end
                end)
                item.fold = self.ui:button({
                    size = { 0, 24, 0, ROW - 6 },
                    fontSize = 15,
                    backgroundTransparency = 1,
                }, self.tree)
                item.fold:connect('press', function()
                    if item.row then
                        local node = item.row.node
                        self.collapsed[node] = not self.collapsed[node]
                        self:refreshTree()
                    end
                end)
                item.chip = self.ui:container({
                    size = { 0, 8, 0, 18 },
                    backgroundColor = DEFAULT_CHIP,
                }, self.tree)
                self.ui:create('UICorner', { radius = { 0, 3 } }, item.chip)
                item.name = self.ui:text({
                    size = { 0, 10, 0, ROW - 6 },
                    fontSize = 14,
                    align = 'left',
                }, self.tree)
                item.class = self.ui:text({
                    size = { 0, 10, 0, ROW - 6 },
                    fontSize = 12,
                    align = 'left',
                    textColor = { 0.5, 0.6, 0.7 },
                }, self.tree)
                self.ui:create('UICorner', { radius = { 0, 6 } }, item.background)
                self.rowPool[i] = item
            end
            local row = self.rows[first + i - 1]
            item.row = row
            for _, part in ipairs({ item.background, item.fold, item.chip, item.name, item.class }) do
                part.visible = row ~= nil
            end
            if row then
                local index = first + i - 1
                local y = (index - 1) * ROW + 1
                local indent = 6 + row.depth * INDENT
                local name = label(row)
                local className = row.node.className or 'Node'
                item.background.position = { 0, 0, 0, y }
                item.background.size = { 0, width, 0, ROW - 2 }
                item.background.backgroundColor = row.node == self.selected and SELECTED
                    or (index % 2 == 0 and ROW_ALT or ROW_COLOR)
                item.fold.position = { 0, indent, 0, y + 2 }
                item.fold.text = #Tree.children(row.node) > 0
                        and (self.collapsed[row.node] and '+' or '-')
                    or ''
                item.chip.position = { 0, indent + 28, 0, y + 8 }
                item.chip.backgroundColor = WorkspaceRows.chipColor(className)
                local nameWidth = #name * NAME_WIDTH + 26
                item.name.position = { 0, indent + 42, 0, y + 2 }
                item.name.size = { 0, nameWidth, 0, ROW - 6 }
                item.name.text = name
                item.class.position = { 0, indent + 46 + nameWidth, 0, y + 2 }
                item.class.size = { 0, #className * CLASS_WIDTH + 22, 0, ROW - 6 }
                item.class.text = className
                row.button = item.background
            end
        end
        for i = #self.rowPool, count + 1, -1 do
            local item = self.rowPool[i]
            for _, part in ipairs({ item.background, item.fold, item.chip, item.name, item.class }) do
                part:destroy()
            end
            self.rowPool[i] = nil
        end
    end
end

return WorkspaceRows
