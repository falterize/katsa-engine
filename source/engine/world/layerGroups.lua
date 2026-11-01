local ipairs = require('source.engine.math.array').ipairs
local Groups = require('source.engine.core.groups')
local LayerGroups = {}

function LayerGroups.install(World3D)
    function World3D:initializeLayerGroups()
        self.layerGroups = Groups.new(function(registry)
            if not self.root then
                return
            end
            for _, node in ipairs(self.root:getDescendants()) do
                if (node._world or node._sceneWorld) == self then
                    for _, key in ipairs({ 'layerGroup', 'shadowGroup' }) do
                        if registry.renamed and node[key] == registry.renamed[1] then
                            node[key] = registry.renamed[2]
                        end
                        if node[key] and not registry.bits[node[key]] then
                            node[key] = 'Default'
                        end
                    end
                end
            end
        end)
        self.layerGroups:add('Player')
        self.layerGroups:add('SceneCamera')
        self.layerGroups:set('SceneCamera', 'Player', false)
    end

    function World3D:resolveLayerGroup(node)
        local registry = self.layerGroups
        if not node.layerGroup then
            node.layerGroup = node.layers == 2 and 'Player'
                or node:isA('Camera3D') and node.layers == 1 and 'SceneCamera'
                or 'Default'
        end
        local group = registry:canonical(node.layerGroup)
        assert(registry.bits[group], 'Unknown layer group: ' .. tostring(group))
        if
            node._groupRevision ~= registry.revision
            or node._resolvedGroup ~= group
            or node._resolvedShadow ~= node.shadowGroup
        then
            node.layerGroup = group
            node.layers = node:isA('Camera3D') and registry.masks[group] or registry.bits[group]
            if node.shadowGroup then
                assert(registry.masks[node.shadowGroup], 'Unknown shadow group')
                node.shadowLayers = registry.masks[node.shadowGroup]
            end
            node._groupRevision, node._resolvedGroup, node._resolvedShadow =
                registry.revision, group, node.shadowGroup
            node.shadowRevision = (node.shadowRevision or 0) + 1
        end
    end
end

return LayerGroups
