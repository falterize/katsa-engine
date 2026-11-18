-- Move, Rotate and Scale: places the gizmo over the selection, picks handles from the mouse ray
-- (core/gizmoMath), drags them (core/snap math) and records one undo step per drag.
-- Assumption: the parents of edited nodes only translate (no rotation or scale), which holds
-- for the Level and for groups made by the editor; the gizmo is placed with the parent's offset.
local Affine = require('source.engine.math.affine')
local Gizmo = require('../view.gizmo')
local GizmoMath = require('../core.gizmoMath')
local M = require('source.engine.math.math3d')
local Picking = require('source.engine.world.picking')
local Snap = require('../core.snap')
local TreeModel = require('../core.treeModel')

local Tool = {}
Tool.__index = Tool

local ZERO, ONE = { 0, 0, 0 }, { 1, 1, 1 }
local INDEX = { x = 1, y = 2, z = 3 }
local PLANE = { xy = { 1, 2 }, yz = { 2, 3 }, xz = { 1, 3 } }

local function copy(v)
    return { v[1], v[2], v[3] }
end

-- While a node is dragged onto a surface the node itself must not be hit by the pick ray.
local function setQueryable(drag, queryable)
    if not queryable then
        drag.queried = {}
        local function visit(node)
            if node.canQuery ~= nil then
                drag.queried[#drag.queried + 1] = { node = node, value = node.canQuery }
                node.canQuery = false
            end
            for _, child in ipairs(node.children) do
                visit(child)
            end
        end
        for _, entry in ipairs(drag.nodes) do
            visit(entry.node)
        end
    else
        for _, saved in ipairs(drag.queried or {}) do
            if not saved.node.destroyed then
                saved.node.canQuery = saved.value
            end
        end
        drag.queried = nil
    end
end

function Tool.new(content)
    local self = setmetatable({ content = content }, Tool)
    self.gizmo = Gizmo.new(content.world)
    self.origin, self.direction = {}, {}
    return self
end

-- Top-level selected nodes that are not locked.
function Tool:targets()
    local content, result = self.content, {}
    for _, node in ipairs(TreeModel.topLevel(content.selection:items(), function(n)
        return n.parent
    end)) do
        if not content.ops:isLocked(node) then
            result[#result + 1] = node
        end
    end
    return result
end

-- The pivot (parent space), its world position and the handle axes for the current selection.
function Tool:frameState()
    local content = self.content
    local nodes = self:targets()
    if #nodes == 0 then
        return nil
    end
    local primary = nodes[#nodes]
    local pivot = copy(primary.position)
    if content.pivotMode == 'Center' and #nodes > 1 then
        pivot = { 0, 0, 0 }
        for _, node in ipairs(nodes) do
            pivot[1], pivot[2], pivot[3] = pivot[1] + node.position[1], pivot[2] + node.position[2], pivot[3] + node.position[3]
        end
        pivot[1], pivot[2], pivot[3] = pivot[1] / #nodes, pivot[2] / #nodes, pivot[3] / #nodes
    end
    local world = primary:getWorldMatrix()
    local offset = { world[4] - primary.position[1], world[8] - primary.position[2], world[12] - primary.position[3] }
    local rotation = content.space == 'Local' and primary.rotation or ZERO
    local matrix = M.compose(ZERO, rotation, ONE)
    return {
        nodes = nodes,
        primary = primary,
        pivot = pivot,
        offset = offset,
        world = { pivot[1] + offset[1], pivot[2] + offset[2], pivot[3] + offset[3] },
        rotation = rotation,
        axes = {
            { matrix[1], matrix[5], matrix[9] },
            { matrix[2], matrix[6], matrix[10] },
            { matrix[3], matrix[7], matrix[11] },
        },
    }
end

-- The mouse ray in world space with a unit direction, reusing two tables.
function Tool:ray(x, y)
    local origin, direction = self.content.camera:screenRay(x, y, self.origin, self.direction)
    local length = math.sqrt(direction[1] ^ 2 + direction[2] ^ 2 + direction[3] ^ 2)
    direction[1], direction[2], direction[3] = direction[1] / length, direction[2] / length, direction[3] / length
    return { origin, direction }
end

function Tool:snapping()
    local content = self.content
    return Snap.active(content.snap.enabled, content.fly.map:isDown('editorAdd'))
end

-- Called every frame: shows, places and highlights the gizmo; advances a running drag.
function Tool:update()
    local content = self.content
    local tool = content.tool
    self.gizmo:setTool(tool)
    local frame = tool ~= 'Select' and self:frameState() or nil
    self.frame = frame
    if not frame then
        self.gizmo:hide()
        return
    end
    local camera = content.camera
    local _, _, depth = camera:project(frame.world)
    if not depth then
        self.gizmo:hide()
        return
    end
    local perUnit = camera:pixelsPerUnitAt(depth)
    self.length, self.tolerance = Gizmo.PIXELS / perUnit, 10 / perUnit
    self.gizmo:place(frame.world, frame.rotation, self.length)
    local mouseX, mouseY = katsa.mouse.getX(), katsa.mouse.getY()
    local x, y = content:viewportPoint(mouseX, mouseY, true)
    if self.drag then
        if content.fly.map:isDown('editorPick') and x then
            self:move(x, y)
        else
            self:finish()
        end
    elseif not x or content.fly:isLooking() or content:overUI() or not content:viewportPoint(mouseX, mouseY) then
        self.gizmo:highlight(nil)
    else
        self.gizmo:highlight((GizmoMath.pick(tool, self:ray(x, y), frame.world, frame.axes, self.length, self.tolerance)))
    end
end

function Tool:begin(x, y)
    local frame, content = self.frame, self.content
    if not frame then
        return false
    end
    local ray = self:ray(x, y)
    local handle = GizmoMath.pick(content.tool, ray, frame.world, frame.axes, self.length, self.tolerance)
    if not handle then
        return false
    end
    local drag = { handle = handle, tool = content.tool, frame = frame, x0 = x, nodes = {} }
    local key = frame.primary.size and 'size' or 'scale'
    drag.key = key
    for index, node in ipairs(frame.nodes) do
        drag.nodes[index] = {
            node = node,
            id = content.ops:idOf(node),
            position = copy(node.position),
            rotation = copy(node.rotation),
            size = copy(node[key] or ONE),
        }
    end
    local axisIndex = INDEX[handle]
    if drag.tool == 'Rotate' then
        local point = Snap.planePoint(ray[1], ray[2], frame.world, frame.axes[axisIndex])
        if not point then
            return false
        end
        drag.u0 = { point[1] - frame.world[1], point[2] - frame.world[2], point[3] - frame.world[3] }
    elseif axisIndex then
        drag.t0 = Snap.axisParameter(ray[1], ray[2], frame.world, frame.axes[axisIndex])
        if not drag.t0 then
            return false
        end
    elseif PLANE[handle] then
        local normal = frame.axes[6 - PLANE[handle][1] - PLANE[handle][2]]
        drag.p0 = Snap.planePoint(ray[1], ray[2], frame.world, normal)
        if not drag.p0 then
            return false
        end
        drag.normal = normal
    end
    if drag.tool == 'Move' and PLANE[handle] then
        setQueryable(drag, false)
    end
    self.drag = drag
    return true
end

local function write(entry, position, rotation, size, key)
    local node = entry.node
    if position then
        node.position = copy(position)
    end
    if rotation then
        node.rotation = copy(rotation)
    end
    if size then
        node[key] = copy(size)
    end
end

function Tool:move(x, y)
    local drag, content = self.drag, self.content
    local frame, step = drag.frame, content.snap
    local on = self:snapping()
    local ray = self:ray(x, y)
    local axisIndex = INDEX[drag.handle]
    if drag.tool == 'Move' then
        local delta
        if axisIndex then
            local t = Snap.axisParameter(ray[1], ray[2], frame.world, frame.axes[axisIndex])
            if not t then
                return
            end
            local distance = t - drag.t0
            if on then
                if content.space == 'World' then
                    distance = Snap.value(frame.world[axisIndex] + distance, step.move) - frame.world[axisIndex]
                else
                    distance = Snap.value(distance, step.move)
                end
            end
            local axis = frame.axes[axisIndex]
            delta = { axis[1] * distance, axis[2] * distance, axis[3] * distance }
        else
            local point = Snap.planePoint(ray[1], ray[2], frame.world, drag.normal)
            if not point then
                return
            end
            delta = { point[1] - drag.p0[1], point[2] - drag.p0[2], point[3] - drag.p0[3] }
            -- Surface snap: the pivot follows the first surface under the pointer instead.
            if Snap.active(content.snap.surface, content.fly.map:isDown('editorAdd')) then
                local hit, depth = Picking.raycast(content.world, content.camera, x, y)
                if hit then
                    local origin, direction = content.camera:screenRay(x, y)
                    delta = {
                        origin[1] + direction[1] * depth - frame.world[1],
                        origin[2] + direction[2] * depth - frame.world[2],
                        origin[3] + direction[3] * depth - frame.world[3],
                    }
                    on = false
                end
            end
            if on then
                local pair = PLANE[drag.handle]
                local a, b = frame.axes[pair[1]], frame.axes[pair[2]]
                local da = delta[1] * a[1] + delta[2] * a[2] + delta[3] * a[3]
                local db = delta[1] * b[1] + delta[2] * b[2] + delta[3] * b[3]
                if content.space == 'World' then
                    da = Snap.value(frame.world[pair[1]] + da, step.move) - frame.world[pair[1]]
                    db = Snap.value(frame.world[pair[2]] + db, step.move) - frame.world[pair[2]]
                else
                    da, db = Snap.value(da, step.move), Snap.value(db, step.move)
                end
                delta = { a[1] * da + b[1] * db, a[2] * da + b[2] * db, a[3] * da + b[3] * db }
            end
        end
        for _, entry in ipairs(drag.nodes) do
            write(entry, {
                entry.position[1] + delta[1],
                entry.position[2] + delta[2],
                entry.position[3] + delta[3],
            })
        end
    elseif drag.tool == 'Rotate' then
        local point = Snap.planePoint(ray[1], ray[2], frame.world, frame.axes[axisIndex])
        if not point then
            return
        end
        local u = { point[1] - frame.world[1], point[2] - frame.world[2], point[3] - frame.world[3] }
        local axis = frame.axes[axisIndex]
        local angle = Snap.angleAround(axis, drag.u0, u)
        if on then
            angle = Snap.value(angle, step.rotate)
        end
        drag.angle = angle
        for _, entry in ipairs(drag.nodes) do
            local position = #drag.nodes > 1 and GizmoMath.rotatePoint(entry.position, frame.pivot, axis, angle) or nil
            write(
                entry,
                position,
                GizmoMath.rotateEuler(entry.rotation, axis, angle, false, M.compose, Affine.euler)
            )
        end
    else
        local factor
        if axisIndex then
            local t = Snap.axisParameter(ray[1], ray[2], frame.world, frame.axes[axisIndex])
            if not t then
                return
            end
            factor = Snap.scaleFactor(drag.t0, t)
        else
            factor = 1 + (x - drag.x0) / 200
        end
        if on then
            factor = math.max(step.scale, Snap.value(factor, step.scale))
        end
        for _, entry in ipairs(drag.nodes) do
            local size = copy(entry.size)
            if axisIndex then
                size[axisIndex] = size[axisIndex] * factor
            else
                size = { size[1] * factor, size[2] * factor, size[3] * factor }
            end
            local position
            if not axisIndex and #drag.nodes > 1 then
                position = {
                    frame.pivot[1] + (entry.position[1] - frame.pivot[1]) * factor,
                    frame.pivot[2] + (entry.position[2] - frame.pivot[2]) * factor,
                    frame.pivot[3] + (entry.position[3] - frame.pivot[3]) * factor,
                }
            end
            write(entry, position, nil, size, drag.key)
        end
    end
end

-- Ends the drag: the change is already on the nodes, so only the history is recorded.
function Tool:finish()
    local drag, content = self.drag, self.content
    self.drag = nil
    setQueryable(drag, true)
    local entries, changed = {}, false
    for index, entry in ipairs(drag.nodes) do
        local node = entry.node
        if not node.destroyed then
            local after = {
                position = copy(node.position),
                rotation = copy(node.rotation),
                size = copy(node[drag.key] or ONE),
            }
            for _, name in ipairs({ 'position', 'rotation', 'size' }) do
                for component = 1, 3 do
                    if after[name][component] ~= entry[name][component] then
                        changed = true
                    end
                end
            end
            entries[index] = { id = entry.id, before = entry, after = after }
        end
    end
    if not changed then
        return
    end
    local ops, key = content.ops, drag.key
    local function apply(which)
        for _, entry in ipairs(entries) do
            local node = ops:node(entry.id)
            if node then
                local state = which == 'before' and entry.before or entry.after
                write({ node = node }, state.position, state.rotation, state.size, key)
            end
        end
        content.panels.properties.dirty = true
    end
    content.undo:push({
        name = drag.tool,
        redo = function()
            apply('after')
        end,
        undo = function()
            apply('before')
        end,
    }, true)
    content.panels.properties.dirty = true
end

function Tool:release()
    self.gizmo:release()
end

return Tool
