local Node = require('source.engine.nodes')
return function(test)
    local function check(condition, message)
        test:check(condition, message)
    end
    local a = Node.new('World3D', { name = 'A' })
    local b = Node.new('World3D', { name = 'B' })
    local wa, wb = {}, {}
    a._world, b._world = wa, wb
    local folder = Node.new('Folder', {}, a)
    local inner = Node.new('Folder', {}, folder)
    local mesh = Node.new('Mesh3D', { _world = wa }, inner)

    local function reject(node, parent, message)
        local previous = node.parent
        local count = previous and #previous.children
        local events = 0
        local connection = node:connect('parentChanged', function()
            events = events + 1
        end)
        local ok = pcall(node.setParent, node, parent)
        connection:disconnect()
        check(
            not ok
                and node.parent == previous
                and (not previous or #previous.children == count)
                and events == 0,
            message
        )
    end
    reject(folder, inner, 'Cycles are rejected atomically')
    reject(folder, b, 'Folder transfers validate nested resource ownership')
    folder.parent = nil
    local ok = pcall(folder.setParent, folder, b)
    check(not ok and folder.parent == nil, 'Detached subtrees retain resource ownership')
    folder.parent = a
    mesh.physics = { node = mesh }
    local pivot = Node.new('Node3D', {}, a)
    reject(folder, pivot, 'Folder transfers preserve nested body World3D-space constraints')
    reject(mesh, pivot, 'Body3D parenting rejects spatial ancestors')
    mesh.physics = nil
    local ui = Node.new('ScreenUI', {})
    reject(folder, ui, 'Folder transfers cannot smuggle spatial descendants into ScreenUI')
    reject(a, b, 'World3D nodes remain roots')
    local dying = Node.new('Folder', {}, a)
    dying._destroying = true
    reject(folder, dying, 'Destroying parents reject transfers')
    dying._destroying = nil
    local moved = 0
    local connection = folder:connect('parentChanged', function(parent, old)
        moved = moved + 1
        check(
            parent == dying and old == a and folder.parent == dying,
            'Parent event observes the committed hierarchy'
        )
    end)
    folder.parent = dying
    folder.parent = dying
    check(
        moved == 1 and dying.children[1] == folder,
        'Same-parent assignment adds no duplicate or event'
    )
    connection:disconnect()
    local origin = Node.new('Node3D', { position = { 10, 0, 0 }, rotation = { 0, 90, 0 } }, a)
    local socket = Node.new('Attachment3D', { position = { 0, 0, 2 } }, origin)
    local point = socket:getWorldPosition()
    check(math.abs(point[1] - 8) < 0.0001, 'Rotated attachment composes local translation')
    local revision = socket._transformRevision
    socket:getWorldMatrix()
    check(socket._transformRevision == revision, 'Unchanged transforms reuse their revision')
    origin.position[1] = 20
    check(
        math.abs(socket:getWorldPosition()[1] - 18) < 0.0001,
        'In-place ancestor position changes propagate to Attachment3D'
    )
    origin:destroy()
    check(socket.destroyed, 'Subtree destruction releases descendants')
    a:destroy()
    b:destroy()
    ui:destroy()
end
