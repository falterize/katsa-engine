local Dialog = require('./dialog')

-- The shared group matrix editor behind Interaction groups and Shader layers. `ops` describes a
-- registry: { names, interacts(a, b), set(a, b, value), add(name), rename(from, to), remove(name),
-- canRemove(name), canToggle(a, b), priority?(name), setPriority?(name, value), limit }.
local Matrix = {}

-- `state` = { selected, table, page, add, rename } kept by the dialog.
function Matrix.draw(ig, dialog, state, ops)
    local names = ops.names
    ig.text('%d of %d groups', #names, ops.limit or 30)
    ig.setNextItemWidth(160)
    local addChanged, addText = ig.inputText('##add', state.add or '')
    if addChanged then
        state.add = addText
    end
    ig.sameLine()
    if ig.button('Add') and (state.add or '') ~= '' then
        if Dialog.attempt(dialog, ops.add, state.add) then
            state.selected, state.add = state.add, ''
        end
    end
    if not names[1] then
        return
    end
    local known = false
    for _, name in ipairs(names) do
        known = known or name == state.selected
    end
    if not known then
        state.selected = names[1]
    end
    ig.setNextItemWidth(160)
    local renameChanged, renameText = ig.inputText('##rename', state.rename or state.selected)
    if renameChanged then
        state.rename = renameText
    end
    ig.sameLine()
    if ig.button('Rename') and state.rename and state.rename ~= state.selected then
        if Dialog.attempt(dialog, ops.rename, state.selected, state.rename) then
            state.selected, state.rename = state.rename, nil
        end
    end
    if ops.priority then
        ig.setNextItemWidth(160)
        local moved, priority = ig.dragFloat('Priority', ops.priority(state.selected), 0.1, 0, 0, '%.0f')
        if moved then
            Dialog.attempt(dialog, ops.setPriority, state.selected, priority)
        end
    end
    if ops.canRemove(state.selected) then
        if ig.button('Delete selected') then
            if Dialog.attempt(dialog, ops.remove, state.selected) then
                state.selected = names[1]
            end
        end
        ig.sameLine()
    end
    local _, view = ig.checkbox('Table view', state.table == true)
    state.table = view
    ig.separator()
    if state.table then
        -- Rows against columns; the toggles are symmetric.
        if ig.beginTable('##matrix', #names + 1, nil, 0, 0) then
            ig.tableSetupColumn('', 0, 110)
            for _, name in ipairs(names) do
                ig.tableSetupColumn(name, 0, 52)
            end
            ig.tableHeadersRow()
            for _, a in ipairs(names) do
                ig.tableNextRow()
                ig.tableNextColumn()
                ig.text(a)
                for _, b in ipairs(names) do
                    ig.tableNextColumn()
                    ig.pushID(a .. '|' .. b)
                    if ops.canToggle(a, b) then
                        local changed, value = ig.checkbox('##cell', ops.interacts(a, b))
                        if changed then
                            Dialog.attempt(dialog, ops.set, a, b, value)
                        end
                    else
                        ig.textDisabled('-')
                    end
                    ig.popID()
                end
            end
            ig.endTable()
        end
    else
        ig.text('%s interacts with:', state.selected)
        for _, name in ipairs(names) do
            ig.pushID(name)
            if ops.canToggle(state.selected, name) then
                local changed, value = ig.checkbox(name, ops.interacts(state.selected, name))
                if changed then
                    Dialog.attempt(dialog, ops.set, state.selected, name, value)
                end
            else
                ig.textDisabled(name)
            end
            ig.sameLine(200)
            if ig.smallButton('select') then
                state.selected, state.rename = name, nil
            end
            ig.popID()
        end
    end
    Dialog.status(ig, dialog)
end

return Matrix
