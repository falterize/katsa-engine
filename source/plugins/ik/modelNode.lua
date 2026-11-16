-- Helpers for nodes that sit under a model instance and plug into its Animator as a skeleton
-- modifier (InverseKinematics3D, Ragdoll3D).
local ModelNode = {}

-- The model of the nearest ancestor that is a model instance, or nil.
function ModelNode.modelOf(node)
    local parent = node.parent
    while parent do
        if parent.model and parent.model.nodes then
            return parent.model
        end
        parent = parent.parent
    end
end

-- Registers `node` (it needs `process(animator, dt)` and `priority`) with the model's Animator.
-- The model can be instantiated after the node, so call it every update until it returns true.
function ModelNode.connect(node)
    if node.animator and not node.animator.destroyed then
        return true
    end
    local model = ModelNode.modelOf(node)
    local animator = model and (model.animator or model.controller)
    if not (animator and animator.addModifier) then
        return false
    end
    animator:addModifier(node)
    node.animator = animator
    if not node._connected then
        node._connected = true
        node:onDestroy(function()
            if node.animator then
                node.animator:removeModifier(node)
            end
        end)
    end
    return true
end

return ModelNode
