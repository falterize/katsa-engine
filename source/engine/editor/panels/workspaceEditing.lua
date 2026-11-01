-- Install one cohesive responsibility on the public class.
local Properties = require('source.engine.editor.inspectors.properties')
local utf8 = require('utf8')

local panelColor = { 0.035, 0.055, 0.085 }
local buttonColor = { 0.085, 0.135, 0.19 }
local WorkspaceEditing = {}

function WorkspaceEditing.install(Workspace)
    function Workspace:showKeyboard()
        local node = self.popup and self.popup.focusNode or self.entry
        if self._editingNode ~= node then
            if self._editingNode then
                self._editingNode:blur()
            end
            node.text = self.buffer
            node:syncText():set(self.buffer, true)
            self._editingNode = node
            node:focus(true)
        else
            node:focus()
        end
    end

    function Workspace:beginSearch()
        self.editing = { search = true }
        self.buffer = self.query
        self._editingNode = nil
        self.entry.visible, self.apply.visible, self.cancel.visible = true, true, true
        self.status.text = 'Search by node name or class'
        self.scene.input:reset()
        self:showKeyboard()
    end

    function Workspace:beginEdit(field, component)
        self.editing = { field = field, component = component }
        self.buffer = tostring(self:value(field, component))
        self._editingNode = nil
        self.entry.visible, self.apply.visible, self.cancel.visible = true, true, true
        self.status.text = field.hint or (field.key .. ': enter a value')
        self.scene.input:reset()
        self:showKeyboard()
    end

    function Workspace:cancelEdit()
        if self.editing then
            if self._editingNode then
                self._editingNode:blur()
            end
            self._editingNode = nil
        end
        self.editing = nil
        self.entry.visible, self.apply.visible, self.cancel.visible = false, false, false
    end

    function Workspace:commit()
        if not self.editing then
            return
        end
        if self.editing.popup then
            return self.popup:commitInput()
        end
        if self.editing.search then
            self.query = self.buffer
            self.search.text = self.query ~= '' and ('Search: ' .. self.query) or 'Search nodes…'
            self:cancelEdit()
            self.tree.scrollY = 0
            self:refreshTree()
            self.status.text = 'Found ' .. #self.rows .. ' rows. Select a node.'
            return
        end
        local e = self.editing
        local ok, message = Properties.set(
            self.scene,
            self.selected._editorTarget or self.selected,
            e.field,
            self.buffer,
            e.component
        )
        if ok then
            self:cancelEdit()
            self.status.text = e.field.key .. ' updated'
        else
            self.status.text = message
        end
    end

    function Workspace:textinput(text)
        if not self.editing then
            return
        end
        self._editingNode:insertText(text)
        self.buffer = self._editingNode.text
    end

    function Workspace:keypressed(key)
        if self.popup and key == 'escape' then
            self.popup:close(false)
            return true
        end
        if self.popup and not self.editing then
            if key == 'return' then
                self.popup:close(true)
            end
            return true
        end
        if not self.editing then
            return false
        end
        if key == 'escape' then
            self:cancelEdit()
        elseif key == 'return' or key == 'kpenter' then
            self:commit()
        else
            self._editingNode:editKey(key)
            self.buffer = self._editingNode.text
        end
        return true
    end
end

return WorkspaceEditing
