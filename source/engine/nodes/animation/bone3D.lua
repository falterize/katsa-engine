local Node = require('source.engine.nodes.core.baseNode')

local Bone = Node.define('Bone3D', 'Node3D')
Bone.propertySchema = {
    restPosition = { readOnly = true },
    restRotation = { readOnly = true, labels = { 'X', 'Y', 'Z', 'W' } },
    restScale = { readOnly = true },
}

return Bone
