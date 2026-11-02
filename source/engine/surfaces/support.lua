local Array = require('../math.array')
local ipairs = require('../math.array').ipairs
-- Ownership follows Parent; spatial presentation follows an independent validated reference.
local Support = {}
local Affine = require('../math.affine')

function Support.valid(node, reference)
    if
        not Array.is(reference)
        or not reference._node
        or reference.destroyed
        or reference._destroying
    then
        return false, 'Adornee must be a live spatial node'
    end
    if not reference:isA('Node3D') or reference:isA('BillboardUI') or reference:isA('Decal3D') then
        return false, 'Adornee requires a Mesh3D, Attachment3D or ordinary Node3D'
    end
    if (reference._world or reference._sceneWorld) ~= node._world then
        return false, 'Adornee must belong to the same World3D'
    end
    return true
end

function Support.set(node, reference)
    if reference then
        local ok, reason = Support.valid(node, reference)
        assert(ok, reason)
    end
    if node._adorneeConnection then
        node._adorneeConnection:disconnect()
        node._adorneeConnection = nil
    end
    rawset(node, '_adornee', reference)
    node._adorneeLost = false
    node.supportStatus = 'Ready'
    if reference then
        node._adorneeConnection = reference:connect('destroying', function()
            rawset(node, '_adornee', nil)
            node._adorneeLost = true
            node.drawable = false
            node.supportStatus =
                'Adornee removed; choose another support or explicitly clear Adornee'
            if node._adorneeConnection then
                node._adorneeConnection:disconnect()
                node._adorneeConnection = nil
            end
        end)
    end
    node.dirty = true
    return node
end

function Support.resolve(node)
    if node._adorneeLost then
        return
    end
    local reference = node.adornee
    if not reference then
        reference = node.parent
        while reference and not reference:isA('Node3D') do
            reference = reference.parent
        end
    end
    local ok, reason = Support.valid(node, reference)
    if not ok then
        node.supportStatus = reason
        node.drawable = false
        return
    end
    node.supportStatus = 'Ready'
    return reference
end

function Support.frame(node, reference, renderPose)
    local matrix = renderPose and reference:getRenderWorldMatrix() or reference:getWorldMatrix()
    if node.inheritScale == false then
        matrix = Affine.withoutScale(matrix, node._supportFrame)
        node._supportFrame = matrix
    end
    return matrix
end

function Support.initialize(node, reference)
    rawset(node, 'adornee', nil)
    node:setAdornee(reference)
    node:onDestroy(function()
        if node._adorneeConnection then
            node._adorneeConnection:disconnect()
            node._adorneeConnection = nil
        end
        rawset(node, '_adornee', nil)
    end)
end

function Support.halfExtents(node, reference, camera)
    local dimensions = node.supportSize or { 1, 1, 1 }
    local m = reference:getRenderWorldMatrix()
    if reference:isA('Mesh3D') then
        require('source.engine.graphics.geometry.objectBounds').get(reference)
        local b = reference.geometry.bounds
        dimensions = {
            (b[4] - b[1]) * reference.size[1],
            (b[5] - b[2]) * reference.size[2],
            (b[6] - b[3]) * reference.size[3],
        }
    end
    local world, view = { 0, 0, 0 }, { 0, 0, 0 }
    for axis = 1, 3 do
        for i = 1, 3 do
            world[i] = world[i] + math.abs(m[(i - 1) * 4 + axis]) * dimensions[axis] * 0.5
        end
        for i, basis in ipairs({ camera.right, camera.up, camera.forward }) do
            local dot = 0
            for j = 1, 3 do
                dot = dot + basis[j] * m[(j - 1) * 4 + axis]
            end
            view[i] = view[i] + math.abs(dot) * dimensions[axis] * 0.5
        end
    end
    return view, world
end

return Support
