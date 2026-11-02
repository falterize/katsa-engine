-- Bone pose access for IK. A Skeleton wraps a model instance (`Models.instantiate`) and reads
-- and writes the animated pose of its bones in *model space* (the space of `node.world`,
-- relative to `model.root`). Rotations are {x, y, z, w} quaternions.
--
-- Global (model-space) transforms are derived from the current local TRS of every node, not from
-- the cached `node.world`, so edits made earlier in the same solve are visible immediately.
local M = require('source.engine.math.math3d')
local Quat = require('./quat')

local Skeleton = {}
Skeleton.__index = Skeleton

local IDENTITY = { 0, 0, 0, 1 }

-- Inverse of a row-major affine 4x4 matrix (last row 0 0 0 1).
local function invertAffine(m, out)
    out = out or {}
    local a, b, c, d, e, f, g, h, i = m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]
    local det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if math.abs(det) < 1e-12 then
        det = det < 0 and -1e-12 or 1e-12
    end
    local r11, r12, r13 = (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det
    local r21, r22, r23 = (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det
    local r31, r32, r33 = (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det
    local tx, ty, tz = m[4], m[8], m[12]
    out[1], out[2], out[3], out[4] = r11, r12, r13, -(r11 * tx + r12 * ty + r13 * tz)
    out[5], out[6], out[7], out[8] = r21, r22, r23, -(r21 * tx + r22 * ty + r23 * tz)
    out[9], out[10], out[11], out[12] = r31, r32, r33, -(r31 * tx + r32 * ty + r33 * tz)
    out[13], out[14], out[15], out[16] = 0, 0, 0, 1
    return out
end
Skeleton.invertAffine = invertAffine

function Skeleton.new(model)
    assert(model and model.nodes, 'Skeleton requires an instantiated model with nodes')
    local self = setmetatable({}, Skeleton)
    self.model = model
    self.version = 0
    self.cache = {}
    self.rootMatrix = M.identity()
    self.inverseRoot = M.identity()
    self.scratch = { local_ = {}, rotation = {} }
    self:refresh()
    return self
end

-- Re-reads the model root transform and invalidates every cached bone transform. The modifier
-- base calls this once per pose evaluation.
function Skeleton:refresh()
    local root = self.model.root
    local matrix = root and root.getWorldMatrix and root:getWorldMatrix() or nil
    for i = 1, 16 do
        self.rootMatrix[i] = matrix and matrix[i] or (i % 5 == 1 and 1 or 0)
    end
    invertAffine(self.rootMatrix, self.inverseRoot)
    self.version = self.version + 1
end

function Skeleton:find(name)
    local node = self.model.byNodeName[name]
    assert(node, 'Skeleton has no bone named ' .. tostring(name))
    return node
end

-- Accepts a name or a node and returns the node.
function Skeleton:resolve(bone)
    if type(bone) == 'string' then
        return self:find(bone)
    end
    assert(type(bone) == 'table' and bone.rotation, 'Expected a bone name or a model node')
    return bone
end

function Skeleton:resolveAll(list)
    local nodes = {}
    for i, bone in ipairs(list) do
        nodes[i] = self:resolve(bone)
    end
    return nodes
end

local function global(self, node)
    local entry = self.cache[node]
    if entry and entry.version == self.version then
        return entry
    end
    entry = entry or { matrix = {}, rotation = { 0, 0, 0, 1 } }
    self.cache[node] = entry
    -- Resolve the parent first: the scratch tables below are shared by every recursion level.
    local parent = node.parent
    local p = parent and global(self, parent)
    local localMatrix, localRotation = self.scratch.local_, self.scratch.rotation
    if node.matrix then
        for i = 1, 16 do
            localMatrix[i] = node.matrix[i]
        end
        Quat.fromMatrix(node.matrix, localRotation)
    else
        M.trs(node.translation, node.rotation, node.scale, localMatrix)
        Quat.copy(node.rotation, localRotation)
    end
    if p then
        M.multiply(p.matrix, localMatrix, entry.matrix)
        Quat.multiply(p.rotation, localRotation, entry.rotation)
    else
        for i = 1, 16 do
            entry.matrix[i] = localMatrix[i]
        end
        Quat.copy(localRotation, entry.rotation)
    end
    entry.x, entry.y, entry.z = entry.matrix[4], entry.matrix[8], entry.matrix[12]
    entry.version = self.version
    return entry
end

-- Model-space position of a bone.
function Skeleton:getPosition(bone)
    local entry = global(self, self:resolve(bone))
    return entry.x, entry.y, entry.z
end

-- Model-space rotation of a bone (a shared table: copy it before keeping or editing it).
function Skeleton:getRotation(bone)
    return global(self, self:resolve(bone)).rotation
end

function Skeleton:getLocalRotation(bone, out)
    return Quat.copy(self:resolve(bone).rotation, out)
end

function Skeleton:getLocalPosition(bone)
    local t = self:resolve(bone).translation
    return t[1], t[2], t[3]
end

local function write(self, node, q)
    assert(not node.matrix, 'IK cannot drive node ' .. tostring(node.name) .. ': authored as a matrix')
    local rotation = node.rotation
    rotation[1], rotation[2], rotation[3], rotation[4] = q[1], q[2], q[3], q[4]
    self.version = self.version + 1
end

function Skeleton:setLocalRotation(bone, q)
    local node = self:resolve(bone)
    write(self, node, Quat.normalize(q, {}))
end

function Skeleton:setRotation(bone, q)
    local node = self:resolve(bone)
    local parentRotation = node.parent and global(self, node.parent).rotation or IDENTITY
    local result = Quat.multiply(Quat.conjugate(parentRotation, {}), q, {})
    write(self, node, Quat.normalize(result))
end

-- Applies `delta` (a model-space rotation) on top of the bone's current model-space rotation.
function Skeleton:rotate(bone, delta)
    local node = self:resolve(bone)
    self:setRotation(node, Quat.multiply(delta, global(self, node).rotation, {}))
end

-- Rotates `bone` by the shortest arc that points its direction to `child` at (x, y, z).
function Skeleton:aim(bone, child, x, y, z)
    local node, next = self:resolve(bone), self:resolve(child)
    local a, c = global(self, node), global(self, next)
    local delta = Quat.fromTo(c.x - a.x, c.y - a.y, c.z - a.z, x - a.x, y - a.y, z - a.z)
    self:rotate(node, delta)
end

function Skeleton:toModel(x, y, z)
    return M.transform(self.inverseRoot, x, y, z)
end

function Skeleton:toWorld(x, y, z)
    return M.transform(self.rootMatrix, x, y, z)
end

-- Local rotations of the given nodes, to restore or blend against later.
function Skeleton:snapshot(nodes, out)
    out = out or {}
    for i, node in ipairs(nodes) do
        out[i] = Quat.copy(node.rotation, out[i])
    end
    return out
end

-- Blends the given nodes from a snapshot toward their current rotation. influence 0 restores the
-- snapshot, 1 keeps the solved pose.
function Skeleton:blend(nodes, snapshot, influence)
    for i, node in ipairs(nodes) do
        local blended = Quat.slerp(snapshot[i], node.rotation, influence, {})
        write(self, node, blended)
    end
end

return Skeleton
