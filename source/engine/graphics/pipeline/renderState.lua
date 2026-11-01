local Policy = require('source.engine.nodes.core.propertyPolicy')
local Snapshot = require('source.engine.core.valueSnapshot')
return {
    nodeKeys = Policy.nodeKeys,
    nodeVectors = Policy.nodeVectors,
    meshKeys = Policy.meshKeys,
    meshVectors = Policy.meshVectors,
    surfaceKeys = Policy.surfaceKeys,
    surfaceVectors = Policy.surfaceVectors,
    lightKeys = Policy.lightKeys,
    lightVectors = Policy.lightVectors,
    cameraKeys = Policy.cameraKeys,
    empty = Snapshot.empty,
    scalar = Snapshot.scalar,
    vector = Snapshot.vector,
    fields = Snapshot.fields,
    settings = Snapshot.settings,
}
