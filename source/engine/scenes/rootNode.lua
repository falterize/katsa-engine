local Node = require('../nodes')
local Storage = require('../net.replication.storage')

-- The Game node every scene runtime hangs its world from (`scene.root`): the main World3D and the
-- two storage containers become its children. A scene releases it after its world.
local RootNode = {}

function RootNode.create(world)
    local root = Node.create('Game', { name = 'Game' }, nil, world)
    world.root._worldBoundary = true
    world.root.parent = root
    Storage.install(world, true)
    return root
end

function RootNode.release(root)
    if root and not root.destroyed then
        root:destroy()
    end
end

return RootNode
