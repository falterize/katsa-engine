-- Node replication over real loopback UDP: the server's marked nodes appear on every client,
-- client-side changes stay local, ReplicatedStorage and ServerStorage behave like Roblox's.
local Net = require('source.engine.net')
local World3D = require('source.engine.world.world')

local Module = {}

local function pump(server, clients, frames)
    for _ = 1, frames or 30 do
        server:update(1 / 60)
        for _, client in ipairs(clients) do
            client:update(1 / 60)
        end
    end
end

local function child(parent, name)
    for _, node in ipairs(parent.children) do
        if node.name == name then
            return node
        end
    end
end

function Module.run(self)
    local resources = self.manager.resources:scope()
    local serverWorld, clientWorld, lateWorld =
        World3D.new(resources), World3D.new(resources), World3D.new(resources)
    local port = 47900 + math.floor(os.clock() * 1000) % 90
    local server = Net.Server.new({}, { port = port, maxPlayers = 4 })
    server:replicate(serverWorld)
    server:start()

    self:check(
        serverWorld:create('Folder', { name = 'Plain' }).replicated == false,
        'Every node has a replicated flag that is off by default (the inspector shows it)'
    )
    local storage = server.replication.replicatedStorage
    self:check(
        storage.parent == nil
            and storage.visible == false
            and serverWorld.storage.ServerStorage.parent == nil,
        'Storage containers live outside the world root and are hidden'
    )
    local template = serverWorld:create('Mesh3D', { name = 'Template' }, storage)
    local copy = template:clone({ name = 'TemplateCopy' }, serverWorld.root)
    self:check(
        template:isStored() and not template:isVisible() and copy:isVisible() and not copy:isStored(),
        'Stored templates are hidden and a clone placed in the world is visible'
    )
    local round = serverWorld:create('Folder', { name = 'Round', replicated = true })
    round:setAttribute('Timer', 30)
    local pad = serverWorld:create('Mesh3D', { name = 'Pad', replicated = true }, round)
    pad.replicatedProperties = { 'position' }
    pad.position = { 1, 2, 3 }
    serverWorld:create('Folder', { name = 'Hidden' }):setAttribute('Secret', 1)
    serverWorld:create('Folder', { name = 'Prop' }, server.replication.replicatedStorage)
    serverWorld:create('Folder', { name = 'Private' }, server.replication.serverStorage)

    local function connect(world, name)
        local client = Net.Client.new({}, { address = '127.0.0.1', port = port, name = name })
        client:replicate(world)
        client:connect()
        return client
    end
    local client = connect(clientWorld, 'Ann')
    pump(server, { client })

    local copy = child(clientWorld.root, 'Round')
    self:check(
        copy and copy.className == 'Folder' and copy:getAttribute('Timer') == 30 and copy.replica,
        'A marked server node and its attribute appear on the client'
    )
    local copiedPad = copy and child(copy, 'Pad')
    self:check(
        copiedPad and copiedPad.position[1] == 1 and copiedPad.position[3] == 3,
        'A listed property replicates and the child keeps its parent'
    )
    self:check(
        child(clientWorld.root, 'Hidden') == nil
            and child(client.replication.replicatedStorage, 'Prop') ~= nil
            and child(client.replication.replicatedStorage, 'Private') == nil,
        'Unmarked nodes and ServerStorage stay on the server; ReplicatedStorage replicates'
    )

    round:setAttribute('Timer', 29)
    round:setAttribute('Timer', 28)
    pad.position = { 4, 5, 6 }
    round.name = 'Round2'
    pump(server, { client })
    self:check(
        copy:getAttribute('Timer') == 28 and copiedPad.position[2] == 5 and copy.name == 'Round2',
        'Attribute, property and name changes follow the server'
    )

    local local_ = clientWorld:create('Folder', { name = 'LocalOnly' })
    local_:setAttribute('Mine', true)
    copy:setAttribute('Timer', 5)
    pump(server, { client })
    self:check(
        child(serverWorld.root, 'LocalOnly') == nil
            and round:getAttribute('Timer') == 28
            and local_:getAttribute('Mine') == true,
        'Client-side nodes and edits stay on the client'
    )

    round:setAttribute('Timer', nil)
    pad.parent = nil
    pad:destroy()
    pump(server, { client })
    self:check(
        copy:getAttribute('Timer') == nil and copy.children[1] == nil,
        'A removed attribute and a destroyed server node disappear on the client'
    )

    local late = connect(lateWorld, 'Bob')
    pump(server, { client, late })
    local lateRound = child(lateWorld.root, 'Round2')
    self:check(
        lateRound ~= nil and child(late.replication.replicatedStorage, 'Prop') ~= nil,
        'A client that joins later receives the current replicated tree'
    )

    late:disconnect()
    client:disconnect()
    server:stop()
    for _, world in ipairs({ serverWorld, clientWorld, lateWorld }) do
        world.root:destroy()
    end
end

return Module
