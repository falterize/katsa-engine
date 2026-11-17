-- Node replication over real loopback UDP: the server's marked nodes appear on every client,
-- client-side changes stay local, ReplicatedStorage and ServerStorage behave like Roblox's.
local Net = require('source.engine.net')
local World3D = require('source.engine.world.world')

local Properties = require('source.engine.editor.inspectors.properties')
local Schema = require('source.engine.editor.inspectors.schema')

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
    local Properties = require('source.engine.editor.inspectors.properties')
    local function rowOf(node, key)
        for _, row in ipairs(Properties.list(node)) do
            if row.key == key then
                return row
            end
        end
    end
    self:check(
        storage.className == 'StorageFolder' and rowOf(storage, 'replicated') == nil,
        'The storage containers have no replicated switch in the inspector'
    )
    local watched = serverWorld:create('Mesh3D', {
        name = 'Watched',
        replicated = true,
        replicatedProperties = { 'position', 'color' },
    })
    local listed = rowOf(watched, 'replicatedProperties')
    self:check(
        listed and listed.value == 'position, color' and not listed.readOnly,
        'replicatedProperties shows as an editable list on the server'
    )
    self:check(
        Properties.set(nil, watched, listed, 'position, size') and watched.replicatedProperties[2] == 'size'
            and not Properties.set(nil, watched, listed, 'nonsense'),
        'The list is parsed and unknown property names are rejected'
    )
    local plain = serverWorld:create('Mesh3D', { name = 'Plain' })
    local before = Schema.signature(plain)
    plain.replicated = true
    self:check(
        Schema.signature(plain) ~= before,
        'Switching replicated at run time changes the inspector signature, so the list row appears'
    )
    watched.replica = true
    local mirrored, free = rowOf(watched, 'position'), rowOf(watched, 'brightness')
    self:check(
        mirrored and mirrored.readOnly and not Properties.set(nil, watched, mirrored, '1, 2, 3'),
        'A replicated property is read-only on a client replica'
    )
    self:check(
        not free or not free.readOnly,
        'Properties the server does not replicate stay editable on a replica'
    )
    watched.replica = nil
    watched:destroy()
    -- Tags are plain strings: the planned engine tags look like `#shader-<group>`.
    local tagged = serverWorld:create('Folder', { name = 'Tagged' })
    tagged:addTag('#shader-fx')
    self:check(
        tagged:hasTag('#shader-fx') and serverWorld._node:findByTag('#shader-fx', true) == tagged,
        'A tag may start with # (engine-interpreted tags such as #shader-fx)'
    )
    tagged:removeTag('#shader-fx')
    self:check(not tagged:hasTag('#shader-fx'), 'Removing the tag unbinds it')
    tagged:destroy()
    local template = serverWorld:create('Mesh3D', { name = 'Template' }, storage)
    local copy = template:clone({ name = 'TemplateCopy' }, serverWorld._node)
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

    local copy = child(clientWorld._node, 'Round')
    self:check(
        copy and copy.className == 'Folder' and copy:getAttribute('Timer') == 30 and copy.replica,
        'A marked server node and its attribute appear on the client'
    )
    local replicaRow
    for _, row in ipairs(Properties.list(copy)) do
        if row.key == 'replicated' then
            replicaRow = row
        end
    end
    self:check(
        copy.replicated == true and replicaRow and replicaRow.value == true and replicaRow.readOnly,
        'A client copy reads replicated = true in the inspector, read-only'
    )
    local listRow
    for _, row in ipairs(Properties.list(child(copy, 'Pad') or copy)) do
        if row.key == 'replicatedProperties' then
            listRow = row
        end
    end
    self:check(
        listRow and listRow.readOnly and listRow.value == 'position',
        'A client copy lists the properties the server sends (read-only)'
    )
    local copiedPad = copy and child(copy, 'Pad')
    self:check(
        copiedPad and copiedPad.position[1] == 1 and copiedPad.position[3] == 3,
        'A listed property replicates and the child keeps its parent'
    )
    self:check(
        child(clientWorld._node, 'Hidden') == nil
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
        child(serverWorld._node, 'LocalOnly') == nil
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
    local lateRound = child(lateWorld._node, 'Round2')
    self:check(
        lateRound ~= nil and child(late.replication.replicatedStorage, 'Prop') ~= nil,
        'A client that joins later receives the current replicated tree'
    )

    late:disconnect()
    client:disconnect()
    server:stop()
    for _, world in ipairs({ serverWorld, clientWorld, lateWorld }) do
        world._node:destroy()
    end
end

return Module
