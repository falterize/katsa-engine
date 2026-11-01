-- Install one cohesive responsibility on the public class.
local Tree = require('source.engine.editor.tree.traversal')

local panelColor = { 0.035, 0.055, 0.085 }
local buttonColor = { 0.085, 0.135, 0.19 }
local WorkspaceRows = {}

function WorkspaceRows.install(Workspace)
    function Workspace:refreshTree()
        self.rows = Tree.rows(
            { self.scene.world.root, self.settingsRoot },
            self.collapsed,
            self.group,
            self.query
        )
        self.tree.length = #self.rows * 44
        self.ui:scrollBy(self.tree, 0)
        self:renderRows()
    end

    function Workspace:renderRows()
        local height = self.tree._height or math.max(1, self.ui.height - 174)
        local first = math.max(1, math.floor(self.tree.scrollY / 44) + 1)
        local count = math.ceil(height / 44) + 1
        for i = 1, count do
            local item = self.rowPool[i]
            if not item then
                item = {}
                item.fold = self.ui:button({
                    size = { 0, 24, 0, 40 },
                    fontSize = 15,
                    backgroundColor = buttonColor,
                    onPress = function()
                        if item.row then
                            local node = item.row.node
                            self.collapsed[node] = not self.collapsed[node]
                            self:refreshTree()
                        end
                    end,
                }, self.tree)
                item.button = self.ui:button({
                    size = { 1, -30, 0, 40 },
                    fontSize = 13,
                    textScaled = true,
                    maxTextSize = 13,
                    align = 'left',
                    backgroundColor = buttonColor,
                    onPress = function()
                        if item.row then
                            self:select(item.row.node)
                        end
                    end,
                }, self.tree)
                self.rowPool[i] = item
            end
            local row = self.rows[first + i - 1]
            item.row = row
            item.fold.visible = row ~= nil
            item.button.visible = row ~= nil
            if row then
                local y = (first + i - 2) * 44
                local indent = math.min(row.depth * 10, 50)
                item.fold.position = { 0, indent, 0, y }
                item.button.position = { 0, indent + 26, 0, y }
                item.button.size = { 1, -indent - 28, 0, 40 }
                item.fold.text = #Tree.children(row.node) > 0
                        and (self.collapsed[row.node] and '+' or '−')
                    or '·'
                item.button.text = (row.node.name or row.node.className)
                    .. ' ['
                    .. (row.node.className or 'Node')
                    .. ']'
                item.button.backgroundColor = row.node == self.selected and { 0.1, 0.3, 0.4 }
                    or buttonColor
                row.button = item.button
            end
        end
        for i = #self.rowPool, count + 1, -1 do
            self.rowPool[i].fold:destroy()
            self.rowPool[i].button:destroy()
            self.rowPool[i] = nil
        end
    end
end

return WorkspaceRows
