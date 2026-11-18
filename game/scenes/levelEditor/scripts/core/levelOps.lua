-- Every structural and property change the editor makes, as undoable commands. Nodes are
-- addressed by a stable `EditorId` attribute, not by object: undoing a delete rebuilds the node
-- from a snapshot (a new object with the same id), so older commands still find it.
local Clone = require('source.engine.nodes.core.clone')
local NodeData = require('./nodeData')
local Properties = require('source.engine.editor.inspectors.properties')
local TreeModel = require('./treeModel')

local Ops = {}
Ops.__index = Ops

local ID = 'EditorId'
local LOCKED = 'EditorLocked'

local function parentOf(node)
    return node.parent
end

local function uniqueNames(world, data)
    data.name = Clone.uniqueName(world, data.name)
    for _, child in ipairs(data.children) do
        uniqueNames(world, child)
    end
end

function Ops.new(content)
    local self = setmetatable({ content = content, nextId = 1, byId = {} }, Ops)
    self:adopt(content.level)
    return self
end

function Ops:world()
    return self.content.world
end

function Ops:touch()
    self.content.treeVersion = (self.content.treeVersion or 0) + 1
end

-- Gives every node under `node` (and the node) an id and records it. With `renew`, ids copied by
-- a clone are replaced by fresh ones.
function Ops:adopt(node, renew)
    local id = node:getAttribute(ID)
    if renew or not id or (self.byId[id] and self.byId[id] ~= node) then
        id = self.nextId
        node:setAttribute(ID, id)
    end
    self.nextId = math.max(self.nextId, id + 1)
    self.byId[id] = node
    for _, child in ipairs(node.children) do
        self:adopt(child, renew)
    end
end

function Ops:forget(node)
    local id = node:getAttribute(ID)
    if id and self.byId[id] == node then
        self.byId[id] = nil
    end
    for _, child in ipairs(node.children) do
        self:forget(child)
    end
end

function Ops:idOf(node)
    return node:getAttribute(ID)
end

function Ops:node(id)
    local node = self.byId[id]
    if node and not node.destroyed then
        return node
    end
end

function Ops:isLocked(node)
    while node and node ~= self.content.level do
        if node:getAttribute(LOCKED) then
            return true
        end
        node = node.parent
    end
    return false
end

local function ids(self, nodes)
    local result = {}
    for index, node in ipairs(nodes) do
        result[index] = self:idOf(node)
    end
    return result
end

local function resolve(self, list)
    local result = {}
    for _, id in ipairs(list) do
        local node = self:node(id)
        if node then
            result[#result + 1] = node
        end
    end
    return result
end

-- Selects the nodes with these ids (after an undo or redo changed what exists).
function Ops:select(list)
    self.content.selection:set(resolve(self, list))
end

-- Destroys a node and returns what is needed to bring it back.
function Ops:remove(node)
    local snapshot = {
        data = NodeData.capture(node),
        parentId = self:idOf(node.parent),
        index = nil,
    }
    for position, child in ipairs(node.parent.children) do
        if child == node then
            snapshot.index = position
        end
    end
    self:forget(node)
    self.content.selection:remove(node)
    node:destroy()
    self:touch()
    return snapshot
end

function Ops:restore(snapshot)
    local parent = self:node(snapshot.parentId) or self.content.level
    local node = NodeData.build(self:world(), snapshot.data, parent)
    self:adopt(node)
    -- Rebuilt nodes are appended; put them back where they were among their siblings.
    local siblings = parent.children
    if snapshot.index and snapshot.index < #siblings then
        table.remove(siblings, #siblings)
        table.insert(siblings, snapshot.index, node)
    end
    self:touch()
    return node
end

local function snapshotOf(self, node)
    local index
    for position, child in ipairs(node.parent.children) do
        if child == node then
            index = position
        end
    end
    return { data = NodeData.capture(node), parentId = self:idOf(node.parent), index = index }
end

-- A node that already exists (just created or cloned) becomes one undo step.
function Ops:record(name, nodes)
    local snapshots, nodeIds = {}, ids(self, nodes)
    for index, node in ipairs(nodes) do
        snapshots[index] = snapshotOf(self, node)
    end
    self.content.undo:push({
        name = name,
        redo = function()
            local restored = {}
            for index, snapshot in ipairs(snapshots) do
                self:restore(snapshot)
                restored[index] = snapshot.data.attributes[ID]
            end
            self:select(restored)
        end,
        undo = function()
            for index = #nodeIds, 1, -1 do
                local node = self:node(nodeIds[index])
                if node then
                    snapshots[index] = self:remove(node)
                end
            end
        end,
    }, true)
    self:touch()
end

-- Creates a node under `parent` (the Level by default) and records it.
function Ops:create(class, properties, parent, attributes)
    properties = properties or {}
    if class == 'Mesh3D' and properties.maxDistance == nil then
        properties.maxDistance = 0 -- an editor never culls objects by distance
    end
    local node = self:world():create(class, properties, parent or self.content.level)
    for name, value in pairs(attributes or {}) do
        node:setAttribute(name, value)
    end
    self:adopt(node)
    self:record('Create ' .. class, { node })
    self.content.selection:set({ node })
    return node
end

function Ops:delete(nodes)
    local top = TreeModel.topLevel(nodes, parentOf)
    top = (function()
        local result = {}
        for _, node in ipairs(top) do
            if node ~= self.content.level then
                result[#result + 1] = node
            end
        end
        return result
    end)()
    if #top == 0 then
        return
    end
    local nodeIds, snapshots = ids(self, top), {}
    local function redo()
        for index = 1, #nodeIds do
            local node = self:node(nodeIds[index])
            if node then
                snapshots[index] = self:remove(node)
            end
        end
    end
    self.content.undo:push({
        name = 'Delete',
        redo = redo,
        undo = function()
            local restored = {}
            for index = #snapshots, 1, -1 do
                self:restore(snapshots[index])
                restored[#restored + 1] = snapshots[index].data.attributes[ID]
            end
            self:select(restored)
        end,
    })
end

function Ops:duplicate(nodes)
    local copies = {}
    for _, node in ipairs(TreeModel.topLevel(nodes, parentOf)) do
        if node ~= self.content.level then
            local snapshot = NodeData.capture(node)
            uniqueNames(self:world(), snapshot)
            local copy = NodeData.build(self:world(), snapshot, node.parent)
            self:adopt(copy, true)
            copies[#copies + 1] = copy
        end
    end
    if #copies > 0 then
        self:record('Duplicate', copies)
        self.content.selection:set(copies)
    end
    return copies
end

-- Moves nodes under `newParent`; their local transforms are kept (a group at the origin with
-- no rotation or scale never moves them; other parents shift them with the parent).
-- Moves nodes under `newParent`. With `before` (a sibling under the new parent) they are placed
-- just in front of it, otherwise at the end. One undo step; undo restores parent and order.
function Ops:reparent(nodes, newParent, before)
    local top = TreeModel.topLevel(nodes, parentOf)
    local moving = {}
    for _, node in ipairs(top) do
        moving[node] = true
    end
    local moves = {}
    for _, node in ipairs(top) do
        if node ~= self.content.level and TreeModel.canReparent(node, newParent, parentOf) then
            local next
            local seen = false
            for _, sibling in ipairs(node.parent.children) do
                if seen and not moving[sibling] then
                    next = sibling
                    break
                end
                seen = seen or sibling == node
            end
            moves[#moves + 1] = {
                id = self:idOf(node),
                from = self:idOf(node.parent),
                nextId = next and self:idOf(next) or nil,
            }
        end
    end
    if #moves == 0 then
        return false
    end
    local toId = self:idOf(newParent)
    local beforeId = before and self:idOf(before) or nil
    -- Puts `node` under `parent`, directly in front of `anchor` (or last).
    local function place(node, parent, anchor)
        node:setParent(parent)
        local siblings = parent.children
        if anchor and not anchor.destroyed and anchor ~= node then
            -- setParent to the same parent leaves the node where it was, so take it out by
            -- identity (it is not necessarily last) and insert it in front of the anchor.
            for position, child in ipairs(siblings) do
                if child == node then
                    table.remove(siblings, position)
                    break
                end
            end
            for position, child in ipairs(siblings) do
                if child == anchor then
                    table.insert(siblings, position, node)
                    return
                end
            end
            siblings[#siblings + 1] = node
        end
    end
    local function apply(forward)
        if forward then
            for _, move in ipairs(moves) do
                local node = self:node(move.id)
                if node then
                    place(node, self:node(toId) or self.content.level, beforeId and self:node(beforeId))
                end
            end
        else
            for index = #moves, 1, -1 do
                local move = moves[index]
                local node = self:node(move.id)
                if node then
                    place(node, self:node(move.from) or self.content.level, move.nextId and self:node(move.nextId))
                end
            end
        end
        self:touch()
    end
    self.content.undo:push({
        name = 'Reparent',
        redo = function()
            apply(true)
        end,
        undo = function()
            apply(false)
        end,
    })
    return true
end

function Ops:group(nodes)
    local top = TreeModel.topLevel(nodes, parentOf)
    if #top == 0 or top[1] == self.content.level then
        return
    end
    local undo = self.content.undo
    undo:begin('Group')
    local parent = top[1].parent
    local group = self:world():create('Node3D', { name = 'Group' }, parent)
    self:adopt(group)
    self:record('Create group', { group })
    self:reparent(top, group)
    undo:commit()
    self.content.selection:set({ group })
end

-- Moves the children of a plain group (translation only) up to its parent and removes it.
function Ops:ungroup(group)
    if group == self.content.level or group.className ~= 'Node3D' then
        return false, 'Select a group'
    end
    local rotation, scale = group.rotation or { 0, 0, 0 }, group.scale or { 1, 1, 1 }
    if
        rotation[1] ~= 0 or rotation[2] ~= 0 or rotation[3] ~= 0
        or scale[1] ~= 1 or scale[2] ~= 1 or scale[3] ~= 1
    then
        return false, 'Only groups without rotation or scale can be ungrouped'
    end
    local undo = self.content.undo
    undo:begin('Ungroup')
    local offset = group.position or { 0, 0, 0 }
    local children = {}
    for _, child in ipairs(group.children) do
        children[#children + 1] = child
    end
    for _, child in ipairs(children) do
        local p = child.position
        self:setProperty({ child }, 'position', nil, nil, { p[1] + offset[1], p[2] + offset[2], p[3] + offset[3] })
    end
    self:reparent(children, group.parent)
    self:delete({ group })
    undo:commit()
    self.content.selection:set(children)
    return true
end

-- The inspector row of `key` on a node, or nil.
local function row(node, key)
    for _, entry in ipairs(Properties.list(node)) do
        if entry.key == key then
            return entry
        end
    end
end
Ops.row = row

-- Writes one property (or one vector component) on every node through the engine's own
-- Properties.set rules, as one undo step. `values` may give a whole vector instead.
-- Returns true, or false plus the engine's message.
function Ops:setProperty(nodes, key, component, value, vector)
    local scene = self.content.scene
    local undo = self.content.undo
    local changed = {}
    undo:begin('Edit ' .. key)
    for _, node in ipairs(nodes) do
        local field = row(node, key)
        if not field then
            undo:commit()
            return false, node.name .. ' has no property ' .. key
        end
        local steps = {}
        if vector then
            for index = 1, #vector do
                steps[#steps + 1] = { component = index, value = vector[index] }
            end
        else
            steps[1] = { component = component, value = value }
        end
        for _, step in ipairs(steps) do
            local before = Properties.read(node, field, step.component)
            local ok, message = Properties.set(scene, node, field, step.value, step.component)
            if not ok then
                undo:commit()
                return false, message
            end
            local id, component_ = self:idOf(node), step.component
            local after = step.value
            local function write(to)
                local target = self:node(id)
                if target then
                    local current = row(target, key)
                    if current then
                        Properties.set(scene, target, current, to, component_)
                    end
                end
            end
            undo:push({
                name = 'Edit ' .. key,
                key = 'prop:' .. tostring(id) .. ':' .. key .. ':' .. tostring(component_),
                redo = function()
                    write(after)
                end,
                undo = function()
                    write(before)
                end,
            }, true)
            changed[#changed + 1] = node
        end
    end
    undo:commit()
    undo:seal()
    self:touch()
    return true
end

function Ops:setLocked(nodes, locked)
    for _, node in ipairs(nodes) do
        node:setAttribute(LOCKED, locked or nil)
    end
    self:touch()
end

function Ops:rename(node, text)
    text = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' or node == self.content.level or text == node.name then
        return false
    end
    local id, before = self:idOf(node), node.name
    local function write(to)
        local target = self:node(id)
        if target then
            target.name = to
            self:touch()
        end
    end
    self.content.undo:push({
        name = 'Rename',
        redo = function()
            write(text)
        end,
        undo = function()
            write(before)
        end,
    })
    return true
end

-- Remembers snapshots of the top-level selected nodes; paste builds them again with new names.
function Ops:copy(nodes)
    local clipboard = {}
    for _, node in ipairs(TreeModel.topLevel(nodes, parentOf)) do
        if node ~= self.content.level then
            clipboard[#clipboard + 1] = NodeData.capture(node)
        end
    end
    self.clipboard = clipboard
    return #clipboard
end

function Ops:hasClipboard()
    return self.clipboard ~= nil and #self.clipboard > 0
end

function Ops:paste(parent)
    local pasted = {}
    for _, data in ipairs(self.clipboard or {}) do
        local snapshot = NodeData.clone(data)
        uniqueNames(self:world(), snapshot)
        local fresh = NodeData.build(self:world(), snapshot, parent or self.content.level)
        self:adopt(fresh, true)
        pasted[#pasted + 1] = fresh
    end
    if #pasted > 0 then
        self:record('Paste', pasted)
        self.content.selection:set(pasted)
    end
    return pasted
end

-- Loads a stored model file into the Level as one node that remembers its file (EditorModel).
function Ops:placeModel(path, position)
    local world = self:world()
    -- The root name prefixes every part name, so it must be unique before the model is built.
    local name = NodeData.modelName(world, path:match('([^/]+)%.[^%.]+$') or 'Model')
    local root = world:loadModel(path, { name = name })
    root:setParent(self.content.level)
    root.position = { position[1], position[2], position[3] }
    root:setAttribute('EditorModel', path)
    self:adopt(root)
    self:record('Import model', { root })
    self.content.selection:set({ root })
    return root
end

-- Gives a Mesh3D a colour map: reuses its SurfaceAppearance3D child or creates one.
function Ops:applyTexture(mesh, path)
    for _, child in ipairs(mesh.children) do
        if child.className == 'SurfaceAppearance3D' then
            return self:setProperty({ child }, 'colorMap', nil, path)
        end
    end
    self:create('SurfaceAppearance3D', { colorMap = path }, mesh)
    self.content.selection:set({ mesh })
    return true
end

return Ops
