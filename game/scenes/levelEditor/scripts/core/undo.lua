-- Undo/redo command stack. A command is { name, redo = fn, undo = fn, key = optional }.
-- Commands pushed with the same `key` in a row merge into one (a drag or a typed value becomes
-- one step): the merged command keeps the first undo and takes the latest redo.
-- Transactions group several commands into one step. `version` counts every change (push,
-- undo, redo) so the editor can tell when a file is out of date. Pure Lua.
local Undo = {}
Undo.__index = Undo

function Undo.new(limit)
    return setmetatable({ done = {}, undone = {}, limit = limit or 200, depth = 0, version = 0 }, Undo)
end

local function trim(self)
    while #self.done > self.limit do
        table.remove(self.done, 1)
    end
end

-- Records a command. When `applied` is false the command runs now (redo); when true the change
-- has already been made (a finished drag) and only the history is updated.
function Undo:push(command, applied)
    assert(type(command.redo) == 'function' and type(command.undo) == 'function', 'Bad command')
    if not applied then
        command.redo()
    end
    self.version = self.version + 1
    if self.group then
        self.group[#self.group + 1] = command
        return command
    end
    self.undone = {}
    local last = self.done[#self.done]
    if command.key and last and last.key == command.key and not last.sealed then
        last.redo = command.redo
        return last
    end
    self.done[#self.done + 1] = command
    trim(self)
    return command
end

-- A merge key is only joined to the previous command until the gesture ends.
function Undo:seal()
    local last = self.done[#self.done]
    if last then
        last.sealed = true
    end
end

-- Everything pushed between begin and commit becomes one history step named `name`.
function Undo:begin(name)
    self.depth = self.depth + 1
    if self.depth == 1 then
        self.group, self.groupName = {}, name
    end
end

function Undo:commit()
    assert(self.depth > 0, 'commit without begin')
    self.depth = self.depth - 1
    if self.depth > 0 then
        return
    end
    local group, name = self.group, self.groupName
    self.group, self.groupName = nil, nil
    if #group == 0 then
        return
    end
    self:push({
        name = name,
        redo = function()
            for index = 1, #group do
                group[index].redo()
            end
        end,
        undo = function()
            for index = #group, 1, -1 do
                group[index].undo()
            end
        end,
    }, true)
end

function Undo:canUndo()
    return #self.done > 0
end

function Undo:canRedo()
    return #self.undone > 0
end

function Undo:undo()
    local command = table.remove(self.done)
    if not command then
        return false
    end
    command.undo()
    self.version = self.version + 1
    self.undone[#self.undone + 1] = command
    return true, command.name
end

function Undo:redo()
    local command = table.remove(self.undone)
    if not command then
        return false
    end
    command.redo()
    self.version = self.version + 1
    self.done[#self.done + 1] = command
    return true, command.name
end

function Undo:clear()
    self.done, self.undone = {}, {}
end

return Undo
